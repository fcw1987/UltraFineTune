#import "UFAudioEngine.h"
#import "UFEQ.h"
#import "UFRing.h"
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#include <math.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/*
 Apple API references used for the audio lifecycle:
 https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps
 https://developer.apple.com/documentation/coreaudio/catapdescription/initexcludingprocesses:anddeviceuid:withstream:
 https://developer.apple.com/documentation/coreaudio/catapmutebehavior

 The capture aggregate contains only the process tap, never a physical device.
 A separate AUHAL instance enables only its output bus. A stereo ring buffer
 bridges the callback clocks at the same nominal rate. Hardware volume, default
 output selection, and physical device formats remain under the user's control.
 */

static NSString * const UFErrorDomain = @"local.UltraFineTune.Audio";

typedef NS_ENUM(NSInteger, UFErrorCode) {
    UFErrorUnsupported = 1,
    UFErrorRoute,
    UFErrorCoreAudio,
    UFErrorStream,
    UFErrorDelivery,
    UFErrorCleanup
};

static NSError *UFError(UFErrorCode code, NSString *message, OSStatus status) {
    NSMutableDictionary *info = [@{NSLocalizedDescriptionKey: message} mutableCopy];
    if (status != noErr) {
        info[NSUnderlyingErrorKey] = [NSError errorWithDomain:NSOSStatusErrorDomain
                                                       code:status userInfo:nil];
        info[NSLocalizedFailureReasonErrorKey] =
            [NSString stringWithFormat:@"Core Audio returned error %d.", (int)status];
    }
    return [NSError errorWithDomain:UFErrorDomain code:code userInfo:info];
}

static AudioObjectPropertyAddress UFAddress(AudioObjectPropertySelector selector,
                                             AudioObjectPropertyScope scope) {
    return (AudioObjectPropertyAddress){selector, scope, kAudioObjectPropertyElementMain};
}

static OSStatus UFRead(AudioObjectID object, AudioObjectPropertySelector selector,
                       AudioObjectPropertyScope scope, void *value, UInt32 expectedSize) {
    AudioObjectPropertyAddress address = UFAddress(selector, scope);
    UInt32 size = expectedSize;
    OSStatus result = AudioObjectGetPropertyData(object, &address, 0, NULL, &size, value);
    return result == noErr && size != expectedSize ? kAudioHardwareBadPropertySizeError : result;
}

static NSData *UFObjectList(AudioObjectID object, AudioObjectPropertySelector selector,
                           AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress address = UFAddress(selector, scope);
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(object, &address, 0, NULL, &size) != noErr ||
        size % sizeof(AudioObjectID) != 0 || size > 65536) return nil;
    if (size == 0) return [NSData data];
    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (!data || AudioObjectGetPropertyData(object, &address, 0, NULL,
                                            &size, data.mutableBytes) != noErr ||
        size > data.length || size % sizeof(AudioObjectID) != 0) return nil;
    data.length = size;
    return data;
}

static NSString *UFStringProperty(AudioObjectID object, AudioObjectPropertySelector selector) {
    CFStringRef value = NULL;
    OSStatus result = UFRead(object, selector, kAudioObjectPropertyScopeGlobal,
                             &value, sizeof(value));
    if (result != noErr || !value) return nil;
    if (CFGetTypeID(value) != CFStringGetTypeID()) {
        CFRelease(value);
        return nil;
    }
    return CFBridgingRelease(value);
}

static AudioDeviceID UFDefaultOutput(void) {
    AudioDeviceID device = kAudioObjectUnknown;
    if (UFRead(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultOutputDevice,
                kAudioObjectPropertyScopeGlobal, &device, sizeof(device)) != noErr)
        return kAudioObjectUnknown;
    return device;
}

static AudioDeviceID UFFindDevice(NSString *uid) {
    NSData *devices = UFObjectList(kAudioObjectSystemObject, kAudioHardwarePropertyDevices,
                                  kAudioObjectPropertyScopeGlobal);
    const AudioObjectID *ids = devices.bytes;
    for (NSUInteger i = 0; i < devices.length / sizeof(AudioObjectID); i++) {
        if ([UFStringProperty(ids[i], kAudioDevicePropertyDeviceUID) isEqualToString:uid])
            return ids[i];
    }
    return kAudioObjectUnknown;
}

static BOOL UFIsPhysicalOutput(AudioDeviceID device) {
    UInt32 alive = 0, transport = 0;
    if (UFRead(device, kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal,
                &alive, sizeof(alive)) != noErr || !alive ||
        UFRead(device, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal,
                &transport, sizeof(transport)) != noErr) return NO;
    if (transport == kAudioDeviceTransportTypeAggregate ||
        transport == kAudioDeviceTransportTypeVirtual) return NO;
    NSData *outputs = UFObjectList(device, kAudioDevicePropertyStreams,
                                  kAudioObjectPropertyScopeOutput);
    return outputs.length > 0;
}

static BOOL UFIsStereoFloat(AudioStreamBasicDescription format) {
    UInt32 bytesPerFrame = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? 4 : 8;
    return format.mFormatID == kAudioFormatLinearPCM &&
           (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0 &&
           (format.mFormatFlags & kAudioFormatFlagIsBigEndian) == 0 &&
           (format.mFormatFlags & kAudioFormatFlagIsSignedInteger) == 0 &&
           (format.mFormatFlags & kAudioFormatFlagIsAlignedHigh) == 0 &&
           format.mBitsPerChannel == 32 && format.mChannelsPerFrame == 2 &&
           format.mFramesPerPacket == 1 && format.mBytesPerFrame == bytesPerFrame &&
           format.mBytesPerPacket == bytesPerFrame &&
           isfinite(format.mSampleRate) && format.mSampleRate >= 22050.0 &&
           format.mSampleRate <= 192000.0;
}

static BOOL UFEqualFormats(AudioStreamBasicDescription a, AudioStreamBasicDescription b) {
    return fabs(a.mSampleRate - b.mSampleRate) < 0.01 &&
           a.mFormatID == b.mFormatID && a.mFormatFlags == b.mFormatFlags &&
           a.mBytesPerPacket == b.mBytesPerPacket && a.mFramesPerPacket == b.mFramesPerPacket &&
           a.mBytesPerFrame == b.mBytesPerFrame && a.mChannelsPerFrame == b.mChannelsPerFrame &&
           a.mBitsPerChannel == b.mBitsPerChannel;
}

static BOOL UFSingleStereoStream(AudioDeviceID device, AudioObjectPropertyScope scope,
                                 AudioStreamID *stream, AudioStreamBasicDescription *format) {
    NSData *streams = UFObjectList(device, kAudioDevicePropertyStreams, scope);
    if (streams.length != sizeof(AudioStreamID)) return NO;
    memcpy(stream, streams.bytes, sizeof(*stream));
    memset(format, 0, sizeof(*format));
    return UFRead(*stream, kAudioStreamPropertyVirtualFormat, kAudioObjectPropertyScopeGlobal,
                  format, sizeof(*format)) == noErr &&
           format->mFormatID == kAudioFormatLinearPCM && format->mChannelsPerFrame == 2 &&
           isfinite(format->mSampleRate) && format->mSampleRate >= 22050.0 &&
           format->mSampleRate <= 192000.0;
}

@interface UFAudioDevice ()
@property(nonatomic, copy, readwrite) NSString *uid;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, readwrite) BOOL isDefaultOutput;
@property(nonatomic, readwrite) BOOL supportsStereo;
@property(nonatomic, readwrite) double sampleRate;
@end
@implementation UFAudioDevice
@end

typedef struct {
    float *left;
    float *right;
    size_t stride;
    size_t frames;
} UFStereoBuffer;

typedef struct {
    UFEQ *eq;
    UFRing *ring;
    bool inputPlanar;
    UInt32 maximumOutputFrames;
    atomic_bool alive;
    atomic_bool renderEnabled;
    atomic_bool outputReady;
    atomic_uint fault;
    atomic_uint_fast64_t captureCallbacks;
    atomic_uint_fast64_t outputCallbacks;
    atomic_uint_fast64_t signalBlocks;
} UFRenderState;

static BOOL UFMapStereo(const AudioBufferList *buffers, bool planar, UFStereoBuffer *mapped) {
    if (!buffers) return NO;
    if (planar) {
        if (buffers->mNumberBuffers != 2) return NO;
        const AudioBuffer *left = &buffers->mBuffers[0], *right = &buffers->mBuffers[1];
        if (left->mNumberChannels != 1 || right->mNumberChannels != 1 ||
            !left->mData || !right->mData || left->mDataByteSize == 0 ||
            left->mDataByteSize != right->mDataByteSize || left->mDataByteSize % sizeof(float))
            return NO;
        *mapped = (UFStereoBuffer){left->mData, right->mData, 1,
                                  left->mDataByteSize / sizeof(float)};
    } else {
        if (buffers->mNumberBuffers != 1) return NO;
        const AudioBuffer *buffer = &buffers->mBuffers[0];
        if (buffer->mNumberChannels != 2 || !buffer->mData || !buffer->mDataByteSize ||
            buffer->mDataByteSize % (2 * sizeof(float))) return NO;
        *mapped = (UFStereoBuffer){buffer->mData, (float *)buffer->mData + 1, 2,
                                  buffer->mDataByteSize / (2 * sizeof(float))};
    }
    return YES;
}

static void UFZeroOutput(AudioBufferList *output) {
    if (!output) return;
    for (UInt32 i = 0; i < output->mNumberBuffers; i++) {
        if (output->mBuffers[i].mData)
            memset(output->mBuffers[i].mData, 0, output->mBuffers[i].mDataByteSize);
    }
}

/* Realtime callbacks use C only. The capture callback is the ring's sole
   producer, and the AUHAL playback callback is its sole consumer. */
static OSStatus UFCaptureRender(AudioObjectID device, const AudioTimeStamp *now,
                               const AudioBufferList *input, const AudioTimeStamp *inputTime,
                               AudioBufferList *output, const AudioTimeStamp *outputTime,
                               void *userData) {
    (void)device; (void)now; (void)inputTime; (void)outputTime;
    UFRenderState *state = userData;
    UFZeroOutput(output);
    if (!atomic_load_explicit(&state->alive, memory_order_acquire)) return noErr;
    atomic_fetch_add_explicit(&state->captureCallbacks, 1, memory_order_relaxed);
    bool processing = atomic_load_explicit(&state->renderEnabled, memory_order_acquire);
    if (!input || input->mNumberBuffers == 0) {
        if (processing) {
            atomic_store_explicit(&state->renderEnabled, false, memory_order_release);
            atomic_store_explicit(&state->fault, 1, memory_order_release);
        }
        return noErr;
    }
    if (!processing) {
        for (UInt32 i = 0; i < input->mNumberBuffers; i++) {
            if (!input->mBuffers[i].mData || input->mBuffers[i].mDataByteSize == 0)
                return noErr;
        }
    }
    UFStereoBuffer in = {0};
    if (!UFMapStereo(input, state->inputPlanar, &in) || in.frames > 16384) {
        atomic_store_explicit(&state->renderEnabled, false, memory_order_release);
        atomic_store_explicit(&state->fault, 1, memory_order_release);
        return noErr;
    }
    for (size_t frame = 0; frame < in.frames; frame++) {
        float left = in.left[frame * in.stride], right = in.right[frame * in.stride];
        if ((isfinite(left) && fabsf(left) > 0.0000001f) ||
            (isfinite(right) && fabsf(right) > 0.0000001f)) {
            atomic_fetch_add_explicit(&state->signalBlocks, 1, memory_order_release);
            break;
        }
    }
    ufring_write_stereo(state->ring, in.left, in.stride, in.right, in.stride, in.frames);
    return noErr;
}

static OSStatus UFOutputRender(void *userData, AudioUnitRenderActionFlags *flags,
                              const AudioTimeStamp *time, UInt32 bus,
                              UInt32 frames, AudioBufferList *output) {
    (void)flags; (void)time; (void)bus;
    UFRenderState *state = userData;
    UFZeroOutput(output);
    if (!atomic_load_explicit(&state->alive, memory_order_acquire)) return noErr;
    atomic_fetch_add_explicit(&state->outputCallbacks, 1, memory_order_relaxed);
    UFStereoBuffer out = {0};
    if (!UFMapStereo(output, true, &out) || frames == 0 ||
        frames > state->maximumOutputFrames || out.frames < frames) {
        atomic_store_explicit(&state->renderEnabled, false, memory_order_release);
        atomic_store_explicit(&state->fault, 2, memory_order_release);
        return noErr;
    }
    /* Always drain at the playback cadence, including while the original audio
       remains unmuted. This prevents stale queued audio on activation. */
    size_t supplied = ufring_read_stereo(state->ring, out.left, out.stride,
                                        out.right, out.stride, frames);
    atomic_store_explicit(&state->outputReady, supplied == frames, memory_order_release);
    if (atomic_load_explicit(&state->renderEnabled, memory_order_acquire)) {
        ufeq_process_stereo(state->eq, out.left, out.stride, out.right, out.stride,
                           out.left, out.stride, out.right, out.stride, frames);
    } else {
        UFZeroOutput(output);
    }
    return noErr;
}

@interface UFAudioEngine () {
    AudioDeviceID _deviceID;
    AudioObjectID _tapID;
    AudioDeviceID _aggregateID;
    AudioDeviceIOProcID _ioProcID;
    AudioUnit _outputUnit;
    BOOL _outputInitialized;
    BOOL _outputStarted;
    AudioStreamID _physicalStream;
    AudioStreamID _inputStream;
    AudioStreamBasicDescription _physicalFormat;
    AudioStreamBasicDescription _tapFormat;
    AudioStreamBasicDescription _inputFormat;
    AudioStreamBasicDescription _outputClientFormat;
    UFRenderState *_render;
    CATapDescription *_tapDescription;
    NSString *_deviceUID;
    NSTimer *_watchdog;
    uint64_t _lastCaptureCount;
    uint64_t _lastOutputCount;
    uint64_t _lastSignalCount;
    uint64_t _lastUnderrunCount;
    uint64_t _lastOverrunCount;
    NSTimeInterval _lastCaptureAt;
    NSTimeInterval _lastOutputAt;
    NSTimeInterval _lastSignalAt;
    NSTimeInterval _lastFormatCheck;
    NSTimeInterval _startedAt;
    NSTimeInterval _processingStartedAt;
    float _bass, _mid, _treble, _trim;
    BOOL _bypass;
    BOOL _cleanupFailed;
    size_t _targetFrames;
}
@property(nonatomic, readwrite, getter=isRunning) BOOL running;
@property(nonatomic, readwrite, getter=isProcessing) BOOL processing;
@property(nonatomic, copy, readwrite) NSString *statusText;
@property(nonatomic, readwrite) double sampleRate;
@property(nonatomic, strong, readwrite, nullable) NSError *lastError;
@end

@implementation UFAudioEngine

- (instancetype)init {
    self = [super init];
    if (self) _statusText = @"Ready to tune your display.";
    return self;
}

+ (NSArray<UFAudioDevice *> *)outputDevices {
    NSData *devices = UFObjectList(kAudioObjectSystemObject, kAudioHardwarePropertyDevices,
                                  kAudioObjectPropertyScopeGlobal);
    const AudioObjectID *ids = devices.bytes;
    AudioDeviceID defaultOutput = UFDefaultOutput();
    NSMutableArray<UFAudioDevice *> *result = [NSMutableArray array];
    for (NSUInteger i = 0; i < devices.length / sizeof(AudioObjectID); i++) {
        AudioDeviceID deviceID = ids[i];
        if (!UFIsPhysicalOutput(deviceID)) continue;
        NSString *uid = UFStringProperty(deviceID, kAudioDevicePropertyDeviceUID);
        NSString *name = UFStringProperty(deviceID, kAudioObjectPropertyName);
        if (uid.length == 0 || name.length == 0) continue;
        UFAudioDevice *device = [UFAudioDevice new];
        device.uid = uid;
        device.name = name;
        device.isDefaultOutput = deviceID == defaultOutput;
        AudioStreamID stream = 0;
        AudioStreamBasicDescription format = {0};
        device.supportsStereo = UFSingleStereoStream(deviceID, kAudioObjectPropertyScopeOutput, &stream, &format);
        device.sampleRate = device.supportsStereo ? format.mSampleRate : 0;
        [result addObject:device];
    }
    [result sortUsingComparator:^NSComparisonResult(UFAudioDevice *a, UFAudioDevice *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    return result;
}

+ (NSString *)defaultOutputDeviceUID {
    return UFStringProperty(UFDefaultOutput(), kAudioDevicePropertyDeviceUID);
}


+ (NSDictionary *)hardwareSnapshot {
    AudioObjectPropertyAddress address = UFAddress(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal);
    UInt32 size = 0;
    OSStatus listStatus = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size);
    AudioDeviceID defaultOutput = UFDefaultOutput(), systemOutput = 0;
    UFRead(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultSystemOutputDevice,
           kAudioObjectPropertyScopeGlobal, &systemOutput, sizeof(systemOutput));
    NSMutableArray *outputs = [NSMutableArray new];
    for (UFAudioDevice *device in [self outputDevices]) {
        AudioDeviceID deviceID = UFFindDevice(device.uid);
        NSMutableDictionary *item = [@{@"uid": device.uid, @"name": device.name,
            @"defaultOutput": @(deviceID == defaultOutput), @"systemOutput": @(deviceID == systemOutput),
            @"stereoSupported": @(device.supportsStereo), @"sampleRate": @(device.sampleRate)} mutableCopy];
        UInt32 frames = 0, transport = 0;
        if (UFRead(deviceID, kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal, &frames, sizeof(frames)) == noErr)
            item[@"bufferFrames"] = @(frames);
        if (UFRead(deviceID, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal, &transport, sizeof(transport)) == noErr) {
            char type[] = {(char)(transport >> 24), (char)(transport >> 16), (char)(transport >> 8), (char)transport, 0};
            item[@"transport"] = [NSString stringWithUTF8String:type] ?: @"unknown";
        }
        NSString *manufacturer = UFStringProperty(deviceID, kAudioObjectPropertyManufacturer);
        if (manufacturer) item[@"manufacturer"] = manufacturer;
        NSMutableArray *volume = [NSMutableArray new];
        for (UInt32 channel = 0; channel <= 2; channel++) {
            AudioObjectPropertyAddress volumeAddress = {kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, channel};
            Float32 scalar = 0; UInt32 scalarSize = sizeof(scalar);
            if (AudioObjectHasProperty(deviceID, &volumeAddress) &&
                AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, NULL, &scalarSize, &scalar) == noErr && isfinite(scalar))
                [volume addObject:@{@"channel": @(channel), @"scalar": @(scalar)}];
            AudioObjectPropertyAddress muteAddress = {kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput, channel};
            UInt32 mute = 0, muteSize = sizeof(mute);
            if (AudioObjectHasProperty(deviceID, &muteAddress) &&
                AudioObjectGetPropertyData(deviceID, &muteAddress, 0, NULL, &muteSize, &mute) == noErr)
                item[[NSString stringWithFormat:@"muteChannel%u", (unsigned)channel]] = @(mute != 0);
        }
        item[@"volumeScalars"] = volume;
        [outputs addObject:item];
    }
    return @{@"schemaVersion": @1, @"mode": @"read-only; no audio capture or playback",
             @"deviceListStatus": @(listStatus), @"deviceListBytes": @(size),
             @"defaultOutputUID": [self defaultOutputDeviceUID] ?: [NSNull null],
             @"outputs": outputs};
}

+ (NSDictionary *)offStateSelfTest {
    UFAudioEngine *engine = [UFAudioEngine new];
    [engine setBass:6 mid:-6 treble:3 trim:-12 bypass:YES];
    NSError *error = nil;
    BOOL invalidRejected = ![engine startWithDeviceUID:@"local.UltraFineTune.nonexistent-self-test" error:&error] && error != nil;
    BOOL noResources = !engine.running && !engine.processing && !engine->_render && !engine->_tapID &&
        !engine->_aggregateID && !engine->_outputUnit && !engine->_ioProcID && !engine->_cleanupFailed;
    [engine stop]; [engine stop];
    BOOL stopSafe = !engine.running && !engine.processing && engine.sampleRate == 0 && !engine.lastError;
    return @{@"passed": @(invalidRejected && noResources && stopSafe), @"invalidDeviceRejected": @(invalidRejected),
             @"noAudioResourcesCreated": @(noResources), @"repeatedStopSafe": @(stopSafe)};
}

- (float)peak {
    return _render && self.processing ? ufeq_peak(_render->eq) : 0.0f;
}

- (uint64_t)clipCount {
    return _render ? ufeq_clip_count(_render->eq) : 0;
}

- (float)headroomDB {
    UFEQMeters meters = {0};
    if (_render) ufeq_get_meters(_render->eq, &meters);
    return meters.headroom_db;
}

- (double)bufferDurationMS {
    return self.sampleRate > 0 ? 1000.0 * _targetFrames / self.sampleRate : 0;
}

- (void)setBass:(float)bass mid:(float)mid treble:(float)treble
           trim:(float)trim bypass:(BOOL)bypass {
    NSAssert([NSThread isMainThread], @"Audio controls belong to the main thread.");
    _bass = bass; _mid = mid; _treble = treble; _trim = trim; _bypass = bypass;
    if (_render) ufeq_set_controls(_render->eq, bass, mid, treble, trim, bypass);
}

- (OSStatus)applyMuteBehavior:(CATapMuteBehavior)behavior {
    if (_tapID == kAudioObjectUnknown || !_tapDescription) return noErr;
    [_tapDescription setMuteBehavior:behavior];
    /* The property payload is a pointer to a CATapDescription object. */
    void *description = (__bridge void *)_tapDescription;
    AudioObjectPropertyAddress address = UFAddress(kAudioTapPropertyDescription,
                                                   kAudioObjectPropertyScopeGlobal);
    return AudioObjectSetPropertyData(_tapID, &address, 0, NULL,
                                      sizeof(description), &description);
}

- (NSError *)validateSession {
    UInt32 alive = 0;
    if (_deviceID == kAudioObjectUnknown ||
        UFRead(_deviceID, kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal,
               &alive, sizeof(alive)) != noErr || !alive ||
        ![UFStringProperty(_deviceID, kAudioDevicePropertyDeviceUID) isEqualToString:_deviceUID])
        return UFError(UFErrorRoute, @"The selected display was disconnected. Reconnect it, then start tuning again.", noErr);
    if (UFDefaultOutput() != _deviceID)
        return UFError(UFErrorRoute, @"The Mac's sound output changed. Select your display in Sound settings, then start tuning again.", noErr);
    AudioStreamID physical = 0, input = 0;
    AudioStreamBasicDescription physicalFormat = {0}, inputFormat = {0}, tapFormat = {0};
    Float64 nominalRate = 0, aggregateRate = 0;
    NSData *aggregateOutputs = UFObjectList(_aggregateID, kAudioDevicePropertyStreams,
                                           kAudioObjectPropertyScopeOutput);
    if (!UFSingleStereoStream(_deviceID, kAudioObjectPropertyScopeOutput, &physical, &physicalFormat) ||
        !UFSingleStereoStream(_aggregateID, kAudioObjectPropertyScopeInput, &input, &inputFormat) ||
        !UFIsStereoFloat(inputFormat) ||
        physical != _physicalStream || input != _inputStream ||
        !UFEqualFormats(physicalFormat, _physicalFormat) || !UFEqualFormats(inputFormat, _inputFormat) ||
        aggregateOutputs == nil || aggregateOutputs.length != 0 ||
        UFRead(_tapID, kAudioTapPropertyFormat, kAudioObjectPropertyScopeGlobal,
                &tapFormat, sizeof(tapFormat)) != noErr || !UFEqualFormats(tapFormat, _tapFormat) ||
        UFRead(_deviceID, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal,
                &nominalRate, sizeof(nominalRate)) != noErr ||
        UFRead(_aggregateID, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal,
                &aggregateRate, sizeof(aggregateRate)) != noErr ||
        fabs(nominalRate - self.sampleRate) >= 0.01 || fabs(aggregateRate - self.sampleRate) >= 0.01)
        return UFError(UFErrorStream, @"The audio format changed. Tuning stopped so you can start it again using the new format.", noErr);
    if (_outputUnit) {
        AudioDeviceID outputDevice = 0;
        UInt32 inputEnabled = 1;
        AudioStreamBasicDescription client = {0}, hardware = {0};
        UInt32 size = sizeof(outputDevice);
        OSStatus status = AudioUnitGetProperty(_outputUnit, kAudioOutputUnitProperty_CurrentDevice,
                                               kAudioUnitScope_Global, 0, &outputDevice, &size);
        if (status != noErr || outputDevice != _deviceID) return UFError(UFErrorRoute, @"The playback device changed. Start tuning again to reconnect.", status);
        size = sizeof(inputEnabled);
        status = AudioUnitGetProperty(_outputUnit, kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Input, 1, &inputEnabled, &size);
        if (status != noErr || inputEnabled != 0)
            return UFError(UFErrorStream, @"The playback unit's input configuration changed. Tuning stopped.", status);
        size = sizeof(client);
        status = AudioUnitGetProperty(_outputUnit, kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input, 0, &client, &size);
        if (status != noErr || !UFEqualFormats(client, _outputClientFormat))
            return UFError(UFErrorStream, @"The playback format changed. Start tuning again to reconnect.", status);
        size = sizeof(hardware);
        status = AudioUnitGetProperty(_outputUnit, kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output, 0, &hardware, &size);
        if (status != noErr || fabs(hardware.mSampleRate - self.sampleRate) >= 0.01)
            return UFError(UFErrorStream, @"The playback sample rate changed. Start tuning again to reconnect.", status);
    }
    return nil;
}

- (NSError *)prepareOutputUnit {
    AudioComponentDescription componentDescription = {0};
    componentDescription.componentType = kAudioUnitType_Output;
    componentDescription.componentSubType = kAudioUnitSubType_HALOutput;
    componentDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    AudioComponent component = AudioComponentFindNext(NULL, &componentDescription);
    if (!component) return UFError(UFErrorCoreAudio, @"The Mac's output audio unit is unavailable.", noErr);
    OSStatus status = AudioComponentInstanceNew(component, &_outputUnit);
    if (status != noErr || !_outputUnit) return UFError(UFErrorCoreAudio, @"The playback unit could not be created.", status);

    /* Apple TN2091: configure IO first, then device, then the client format.
       Input bus 1 remains disabled for the full life of this AUHAL instance. */
    UInt32 disabled = 0, enabled = 1;
    status = AudioUnitSetProperty(_outputUnit, kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input, 1, &disabled, sizeof(disabled));
    if (status != noErr) return UFError(UFErrorCoreAudio, @"The playback unit could not disable physical audio input.", status);
    status = AudioUnitSetProperty(_outputUnit, kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Output, 0, &enabled, sizeof(enabled));
    if (status != noErr) return UFError(UFErrorCoreAudio, @"The playback unit could not enable speaker output.", status);
    status = AudioUnitSetProperty(_outputUnit, kAudioOutputUnitProperty_CurrentDevice,
                                  kAudioUnitScope_Global, 0, &_deviceID, sizeof(_deviceID));
    if (status != noErr) return UFError(UFErrorCoreAudio, @"The playback unit could not connect to your selected display.", status);
    UInt32 readEnabled = 1, propertySize = sizeof(readEnabled);
    status = AudioUnitGetProperty(_outputUnit, kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input, 1, &readEnabled, &propertySize);
    if (status != noErr || readEnabled != 0)
        return UFError(UFErrorCoreAudio, @"The app could not verify that physical input is disabled.", status);

    AudioStreamBasicDescription hardwareFormat = {0};
    propertySize = sizeof(hardwareFormat);
    status = AudioUnitGetProperty(_outputUnit, kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output, 0, &hardwareFormat, &propertySize);
    if (status != noErr || fabs(hardwareFormat.mSampleRate - self.sampleRate) >= 0.01 ||
        hardwareFormat.mChannelsPerFrame != 2)
        return UFError(UFErrorStream, @"The selected output is not currently using the expected stereo sample rate.", status);
    _outputClientFormat = (AudioStreamBasicDescription){0};
    _outputClientFormat.mSampleRate = hardwareFormat.mSampleRate;
    _outputClientFormat.mFormatID = kAudioFormatLinearPCM;
    _outputClientFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
    _outputClientFormat.mBytesPerPacket = sizeof(float);
    _outputClientFormat.mFramesPerPacket = 1;
    _outputClientFormat.mBytesPerFrame = sizeof(float);
    _outputClientFormat.mChannelsPerFrame = 2;
    _outputClientFormat.mBitsPerChannel = 32;
    status = AudioUnitSetProperty(_outputUnit, kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input, 0, &_outputClientFormat, sizeof(_outputClientFormat));
    if (status != noErr) return UFError(UFErrorStream, @"The playback unit could not use the equalizer's stereo format.", status);
    UInt32 maximumFrames = 4096;
    status = AudioUnitSetProperty(_outputUnit, kAudioUnitProperty_MaximumFramesPerSlice,
                                  kAudioUnitScope_Global, 0, &maximumFrames, sizeof(maximumFrames));
    if (status != noErr) return UFError(UFErrorStream, @"The playback unit could not configure its audio buffer limit.", status);
    propertySize = sizeof(maximumFrames);
    status = AudioUnitGetProperty(_outputUnit, kAudioUnitProperty_MaximumFramesPerSlice,
                                  kAudioUnitScope_Global, 0, &maximumFrames, &propertySize);
    if (status != noErr || maximumFrames == 0 || maximumFrames > 8192)
        return UFError(UFErrorStream, @"The playback unit returned an unsupported audio buffer size.", status);
    _render->maximumOutputFrames = maximumFrames;
    AURenderCallbackStruct callback = {UFOutputRender, _render};
    status = AudioUnitSetProperty(_outputUnit, kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input, 0, &callback, sizeof(callback));
    if (status != noErr) return UFError(UFErrorCoreAudio, @"The playback callback could not be installed.", status);
    status = AudioUnitInitialize(_outputUnit);
    if (status != noErr) return UFError(UFErrorCoreAudio, @"The display's playback unit could not be initialized.", status);
    _outputInitialized = YES;
    return nil;
}

- (BOOL)startWithDeviceUID:(NSString *)uid error:(NSError **)error {
    if (![NSThread isMainThread]) {
        if (error) *error = UFError(UFErrorUnsupported, @"Start audio tuning from the app's main thread.", noErr);
        return NO;
    }
    if (self.running) [self stop];
    self.lastError = nil;
    if (_cleanupFailed) {
        NSError *failure = UFError(UFErrorCleanup, @"Quit and reopen UltraFine Tune before starting a new session. Core Audio could not fully release the previous session.", noErr);
        self.lastError = failure;
        if (error) *error = failure;
        return NO;
    }
    NSError *failure = nil;
    OSStatus status = noErr;
    if (@available(macOS 14.2, *)) {
        _deviceID = UFFindDevice(uid);
        if (_deviceID == kAudioObjectUnknown || !UFIsPhysicalOutput(_deviceID)) {
            failure = UFError(UFErrorRoute, @"Choose a connected physical audio output.", noErr);
        } else if (UFDefaultOutput() != _deviceID) {
            failure = UFError(UFErrorRoute, @"First select this display as your Mac's sound output in System Settings, Sound, Output. Then return here and start tuning.", noErr);
        } else if (!UFSingleStereoStream(_deviceID, kAudioObjectPropertyScopeOutput,
                                         &_physicalStream, &_physicalFormat)) {
            failure = UFError(UFErrorUnsupported, @"This version needs a single stereo PCM output stream. This device currently exposes a different layout.", noErr);
        }
        if (failure) return [self failStart:failure error:error];
        _deviceUID = [uid copy];
        self.sampleRate = _physicalFormat.mSampleRate;

        /* Connect our playback client before requesting its Core Audio process
           object, so the tap can reliably exclude our own output. */
        _render = calloc(1, sizeof(*_render));
        if (!_render) return [self failStart:UFError(UFErrorCoreAudio, @"There was not enough memory to start audio tuning.", noErr) error:error];
        atomic_init(&_render->alive, true);
        atomic_init(&_render->renderEnabled, false);
        atomic_init(&_render->outputReady, false);
        atomic_init(&_render->fault, 0);
        atomic_init(&_render->captureCallbacks, 0);
        atomic_init(&_render->outputCallbacks, 0);
        atomic_init(&_render->signalBlocks, 0);
        if (!atomic_is_lock_free(&_render->captureCallbacks) || !atomic_is_lock_free(&_render->alive) ||
            !atomic_is_lock_free(&_render->fault))
            return [self failStart:UFError(UFErrorUnsupported, @"This processor does not provide the realtime atomic operations required by the audio engine.", noErr) error:error];
        _render->eq = ufeq_create(self.sampleRate);
        UInt32 hardwareFrames = 512;
        if (UFRead(_deviceID, kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal,
                   &hardwareFrames, sizeof(hardwareFrames)) != noErr || hardwareFrames == 0) hardwareFrames = 512;
        size_t targetFrames = (size_t)hardwareFrames * 2;
        if (targetFrames < 1024) targetFrames = 1024;
        if (targetFrames > 8192) targetFrames = 8192;
        _targetFrames = targetFrames;
        _render->ring = ufring_create(32768, targetFrames);
        if (!_render->eq || !_render->ring)
            return [self failStart:UFError(UFErrorCoreAudio, @"The audio processor could not be initialized at this sample rate.", noErr) error:error];
        ufeq_set_controls(_render->eq, _bass, _mid, _treble, _trim, _bypass);
        if ((failure = [self prepareOutputUnit])) return [self failStart:failure error:error];

        status = AudioOutputUnitStart(_outputUnit);
        if (status != noErr)
            return [self failStart:UFError(UFErrorCoreAudio, @"The display's playback unit could not start.", status) error:error];
        _outputStarted = YES;

        pid_t pid = getpid();
        AudioObjectID ownProcess = kAudioObjectUnknown;
        AudioObjectPropertyAddress processAddress = UFAddress(kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                              kAudioObjectPropertyScopeGlobal);
        UInt32 processSize = sizeof(ownProcess);
        for (unsigned attempt = 0; attempt < 5; attempt++) {
            processSize = sizeof(ownProcess);
            status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &processAddress,
                                                sizeof(pid), &pid, &processSize, &ownProcess);
            if (status == noErr && processSize == sizeof(ownProcess) && ownProcess != kAudioObjectUnknown) break;
            [NSThread sleepForTimeInterval:0.02];
        }
        if (status != noErr || processSize != sizeof(ownProcess) || ownProcess == kAudioObjectUnknown)
            return [self failStart:UFError(UFErrorCoreAudio, @"Core Audio could not identify this app's playback process. Quit and reopen the app, then try again.", status) error:error];

        _tapDescription = [[CATapDescription alloc] initExcludingProcesses:@[@(ownProcess)]
                                                             andDeviceUID:uid withStream:0];
        if (!_tapDescription)
            return [self failStart:UFError(UFErrorCoreAudio, @"Core Audio could not describe the audio tap.", noErr) error:error];
        [_tapDescription setName:@"UltraFine Tune audio"];
        [_tapDescription setPrivate:YES];
        [_tapDescription setMuteBehavior:CATapUnmuted];
        status = AudioHardwareCreateProcessTap(_tapDescription, &_tapID);
        if (status != noErr || _tapID == kAudioObjectUnknown)
            return [self failStart:UFError(UFErrorCoreAudio, @"The system audio tap could not be created. Check this app's System Audio Recording permission in Privacy & Security, then try again.", status) error:error];
        NSString *tapUID = UFStringProperty(_tapID, kAudioTapPropertyUID);
        status = UFRead(_tapID, kAudioTapPropertyFormat, kAudioObjectPropertyScopeGlobal,
                        &_tapFormat, sizeof(_tapFormat));
        if (status != noErr || !tapUID || _tapFormat.mFormatID != kAudioFormatLinearPCM ||
            _tapFormat.mChannelsPerFrame != 2 ||
            fabs(_tapFormat.mSampleRate - self.sampleRate) >= 0.01)
            return [self failStart:UFError(UFErrorStream, @"The audio tap returned an unsupported or mismatched format.", status) error:error];
        NSDictionary *composition = @{
            @kAudioAggregateDeviceNameKey: @"UltraFine Tune private audio",
            @kAudioAggregateDeviceUIDKey: [@"local.UltraFineTune." stringByAppendingString:[NSUUID UUID].UUIDString],
            @kAudioAggregateDeviceIsPrivateKey: @YES,
            @kAudioAggregateDeviceTapListKey: @[@{@kAudioSubTapUIDKey: tapUID,
                                                 @kAudioSubTapDriftCompensationKey: @YES}],
            @kAudioAggregateDeviceTapAutoStartKey: @NO
        };
        status = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)composition, &_aggregateID);
        if (status != noErr || _aggregateID == kAudioObjectUnknown)
            return [self failStart:UFError(UFErrorCoreAudio, @"Core Audio could not prepare the private audio capture device.", status) error:error];

        /* Only this app's capture aggregate is configured. No physical device
           is a subdevice, so this cannot change the speaker's sample rate. */
        Float64 captureRate = 0;
        status = UFRead(_aggregateID, kAudioDevicePropertyNominalSampleRate,
                         kAudioObjectPropertyScopeGlobal, &captureRate, sizeof(captureRate));
        if (status != noErr || fabs(captureRate - self.sampleRate) >= 0.01) {
            AudioObjectPropertyAddress rateAddress = UFAddress(kAudioDevicePropertyNominalSampleRate,
                                                               kAudioObjectPropertyScopeGlobal);
            Float64 requestedRate = self.sampleRate;
            status = AudioObjectSetPropertyData(_aggregateID, &rateAddress, 0, NULL,
                                                sizeof(requestedRate), &requestedRate);
            if (status != noErr)
                return [self failStart:UFError(UFErrorStream, @"The private capture device could not match your display's sample rate.", status) error:error];
        }
        BOOL formatReady = NO;
        for (unsigned attempt = 0; attempt < 12; attempt++) {
            if (UFSingleStereoStream(_aggregateID, kAudioObjectPropertyScopeInput, &_inputStream, &_inputFormat) &&
                UFIsStereoFloat(_inputFormat) &&
                fabs(_inputFormat.mSampleRate - self.sampleRate) < 0.01) {
                formatReady = YES;
                break;
            }
            [NSThread sleepForTimeInterval:0.025];
        }
        if (!formatReady)
            return [self failStart:UFError(UFErrorStream, @"Core Audio did not provide matching stereo capture for this output. Try starting again after the device settles.", noErr) error:error];

        _render->inputPlanar = (_inputFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
        if ((failure = [self validateSession])) return [self failStart:failure error:error];
        status = AudioDeviceCreateIOProcID(_aggregateID, UFCaptureRender, _render, &_ioProcID);
        if (status != noErr)
            return [self failStart:UFError(UFErrorCoreAudio, @"Core Audio could not prepare audio capture.", status) error:error];
        status = AudioDeviceStart(_aggregateID, _ioProcID);
        if (status != noErr)
            return [self failStart:UFError(UFErrorCoreAudio, @"Audio capture could not start. Allow System Audio Recording for UltraFine Tune in Privacy & Security, then reopen the app and try again.", status) error:error];
        self.running = YES;
        self.processing = NO;
        self.statusText = @"Waiting for audio. Play something and allow System Audio Recording if prompted.";
        _startedAt = [NSProcessInfo processInfo].systemUptime;
        _lastCaptureAt = _startedAt;
        _lastOutputAt = _startedAt;
        _lastSignalAt = 0;
        _lastFormatCheck = _startedAt;
        _lastCaptureCount = 0;
        _lastOutputCount = 0;
        _lastSignalCount = 0;
        _lastUnderrunCount = 0;
        _lastOverrunCount = 0;
        _processingStartedAt = 0;
        __weak UFAudioEngine *weakSelf = self;
        _watchdog = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            [weakSelf checkSession];
        }];
        [[NSRunLoop mainRunLoop] addTimer:_watchdog forMode:NSRunLoopCommonModes];
        return YES;
    }
    return [self failStart:UFError(UFErrorUnsupported, @"UltraFine Tune requires macOS 14.2 or later.", noErr) error:error];
}

- (BOOL)failStart:(NSError *)failure error:(NSError **)error {
    [self finishWithError:failure notify:NO];
    if (error) *error = self.lastError;
    return NO;
}

- (void)checkSession {
    if (!self.running || !_render) return;
    NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    if (atomic_load_explicit(&_render->fault, memory_order_acquire) != 0) {
        [self finishWithError:UFError(UFErrorStream, @"Core Audio changed an audio buffer layout. Tuning stopped. Start again to reconnect.", noErr) notify:YES];
        return;
    }
    uint64_t captureCount = atomic_load_explicit(&_render->captureCallbacks, memory_order_relaxed);
    uint64_t outputCount = atomic_load_explicit(&_render->outputCallbacks, memory_order_relaxed);
    uint64_t signalCount = atomic_load_explicit(&_render->signalBlocks, memory_order_acquire);
    if (captureCount != _lastCaptureCount) {
        _lastCaptureCount = captureCount;
        _lastCaptureAt = now;
    }
    if (outputCount != _lastOutputCount) {
        _lastOutputCount = outputCount;
        _lastOutputAt = now;
    }
    if (signalCount != _lastSignalCount) {
        _lastSignalCount = signalCount;
        _lastSignalAt = now;
    }
    if (now - _lastOutputAt > 3.0 || now - _lastCaptureAt > 3.0) {
        [self finishWithError:UFError(UFErrorDelivery, @"Core Audio stopped delivering audio. Check the display connection and System Audio Recording permission, then start tuning again.", noErr) notify:YES];
        return;
    }
    if (now - _lastFormatCheck >= 0.5) {
        _lastFormatCheck = now;
        NSError *failure = [self validateSession];
        if (failure) {
            [self finishWithError:failure notify:YES];
            return;
        }
        uint64_t underruns = ufring_underruns(_render->ring);
        uint64_t overruns = ufring_overruns(_render->ring);
        if (self.processing && now - _processingStartedAt > 1.0 &&
            (underruns - _lastUnderrunCount >= 6 || overruns > _lastOverrunCount)) {
            [self finishWithError:UFError(UFErrorDelivery, @"The audio paths could not stay synchronized. Tuning stopped. Close other audio tools and try again.", noErr) notify:YES];
            return;
        }
        _lastUnderrunCount = underruns;
        _lastOverrunCount = overruns;
    }
    if (self.processing && now - _lastSignalAt >= 5.0) {
        /* Silence does not establish permission denial. Reopening the ordinary
           path also prevents a later capture failure from muting indefinitely. */
        atomic_store_explicit(&_render->renderEnabled, false, memory_order_release);
        OSStatus status = [self applyMuteBehavior:CATapUnmuted];
        if (status != noErr) {
            [self finishWithError:UFError(UFErrorCoreAudio, @"The app could not reopen ordinary playback after capture became silent.", status) notify:YES];
            return;
        }
        self.processing = NO;
        self.statusText = @"Waiting for audio. Tuning will resume when captured sound returns.";
    }
    if (!self.processing && signalCount > 0 && now - _lastSignalAt < 0.5 &&
        outputCount > 0 && captureCount > 0 &&
        atomic_load_explicit(&_render->outputReady, memory_order_acquire)) {
        NSError *failure = [self validateSession];
        if (failure) {
            [self finishWithError:failure notify:YES];
            return;
        }
        OSStatus status = [self applyMuteBehavior:CATapMutedWhenTapped];
        if (status != noErr) {
            [self finishWithError:UFError(UFErrorCoreAudio, @"The app could hear audio but could not enable live processing.", status) notify:YES];
            return;
        }
        atomic_store_explicit(&_render->renderEnabled, true, memory_order_release);
        self.processing = YES;
        _processingStartedAt = now;
        _lastUnderrunCount = ufring_underruns(_render->ring);
        _lastOverrunCount = ufring_overruns(_render->ring);
        self.statusText = @"Tuning your display audio.";
    } else if (!self.processing && now - _startedAt >= 15.0) {
        self.statusText = @"Waiting for captured audio. Play sound through the selected display and check System Audio Recording permission.";
    }
}

- (void)finishWithError:(NSError *)failure notify:(BOOL)notify {
    [_watchdog invalidate];
    _watchdog = nil;
    self.running = NO;
    self.processing = NO;
    if (_render) {
        atomic_store_explicit(&_render->renderEnabled, false, memory_order_release);
        atomic_store_explicit(&_render->alive, false, memory_order_release);
    }
    OSStatus firstCleanupError = noErr;
    BOOL callbackDetached = _ioProcID == NULL;
    if (_aggregateID && _ioProcID) {
        OSStatus status = AudioDeviceStop(_aggregateID, _ioProcID);
        if (status != noErr) firstCleanupError = status;
        status = AudioDeviceDestroyIOProcID(_aggregateID, _ioProcID);
        if (status == noErr) {
            callbackDetached = YES;
            _ioProcID = NULL;
        } else if (firstCleanupError == noErr) firstCleanupError = status;
    }
    BOOL outputDetached = _outputUnit == NULL;
    if (_outputUnit) {
        if (_outputStarted) {
            OSStatus status = AudioOutputUnitStop(_outputUnit);
            if (status != noErr && firstCleanupError == noErr) firstCleanupError = status;
            _outputStarted = NO;
        }
        if (_outputInitialized) {
            OSStatus status = AudioUnitUninitialize(_outputUnit);
            if (status != noErr && firstCleanupError == noErr) firstCleanupError = status;
            _outputInitialized = NO;
        }
        OSStatus status = AudioComponentInstanceDispose(_outputUnit);
        if (status == noErr) {
            _outputUnit = NULL;
            outputDetached = YES;
        } else if (firstCleanupError == noErr) firstCleanupError = status;
    }
    /* Try unmuting explicitly as well as removing the mutedWhenTapped reader. */
    OSStatus unmuteStatus = [self applyMuteBehavior:CATapUnmuted];
    if (_aggregateID) {
        OSStatus status = AudioHardwareDestroyAggregateDevice(_aggregateID);
        if (status == noErr || status == kAudioHardwareBadObjectError) {
            _aggregateID = kAudioObjectUnknown;
            _ioProcID = NULL;
            callbackDetached = YES;
        } else if (firstCleanupError == noErr) firstCleanupError = status;
    }
    if (_tapID) {
        OSStatus status = AudioHardwareDestroyProcessTap(_tapID);
        if (status == noErr || status == kAudioHardwareBadObjectError) {
            _tapID = kAudioObjectUnknown;
        } else if (firstCleanupError == noErr) firstCleanupError = status;
    }
    if (firstCleanupError == noErr && _tapID && unmuteStatus != noErr)
        firstCleanupError = unmuteStatus;
    if (_render && callbackDetached && outputDetached) {
        ufring_destroy(_render->ring);
        ufeq_destroy(_render->eq);
        free(_render);
        _render = NULL;
    }
    /* If HAL refuses to detach its callback, preserve its inactive context until
       process exit. Freeing it would create a use after free on the audio thread. */
    _cleanupFailed = _aggregateID != kAudioObjectUnknown || _tapID != kAudioObjectUnknown || !callbackDetached || !outputDetached;
    if (_cleanupFailed) {
        failure = UFError(UFErrorCleanup, @"Core Audio could not completely close this session. Quit UltraFine Tune to release its private audio resources before trying again.", firstCleanupError);
    } else {
        _tapDescription = nil;
        _deviceUID = nil;
        _deviceID = kAudioObjectUnknown;
    }
    self.sampleRate = 0;
    self.lastError = failure;
    self.statusText = failure ? failure.localizedDescription : @"Stopped. Ordinary playback is restored.";
    if (notify && self.stateChanged) self.stateChanged(failure);
}

- (void)stop {
    NSAssert([NSThread isMainThread], @"Stop audio from the main thread.");
    [self finishWithError:nil notify:NO];
}

- (void)dealloc {
    [self finishWithError:nil notify:NO];
}
@end
