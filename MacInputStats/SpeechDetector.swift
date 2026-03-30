import AppKit
import CoreAudio
import Foundation

/// Tracks talk time as the duration the microphone is active (used by another app).
/// Monitors ALL input devices so it catches mic usage regardless of which device
/// macOS routes audio through (AirPods, built-in mic, external mic, etc.).
@MainActor
final class SpeechDetector: ObservableObject {
    @Published private(set) var micInUse = false
    /// Live elapsed seconds for the current mic session (updates every second)
    @Published private(set) var ongoingSessionSeconds: Double = 0

    private var store: StatsStore
    private var monitoredDevices: [AudioDeviceID] = []
    private var deviceListChangedRegistered = false
    private var sessionStartTime: Date?
    private var sessionApp: String?
    private var flushTimer: Timer?
    private var displayTimer: Timer?
    private var pollTimer: Timer?

    init(store: StatsStore) {
        self.store = store
    }

    func start() {
        refreshDevices()
        registerDeviceListChangeListener()
        startPolling()
    }

    func stop() {
        unregisterAllDeviceListeners()
        unregisterDeviceListChangeListener()
        stopTimers()
        pollTimer?.invalidate()
        pollTimer = nil
        if micInUse {
            endSession()
        }
    }

    private var frontmostAppName: String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    }

    // MARK: - Device Discovery

    private func allInputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
        ) == noErr else { return [] }

        return devices.filter { hasInputStreams($0) }
    }

    private func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else {
            return false
        }
        guard size > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer) == noErr else {
            return false
        }
        let bufferList = bufferListPointer.pointee
        return bufferList.mNumberBuffers > 0 && bufferList.mBuffers.mNumberChannels > 0
    }

    private func refreshDevices() {
        unregisterAllDeviceListeners()
        monitoredDevices = allInputDeviceIDs()
        for deviceID in monitoredDevices {
            registerListener(for: deviceID)
        }
        checkAllDevices()
    }

    // MARK: - Per-Device Listeners

    private func registerListener(for deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            deviceID, &address, DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.checkAllDevices()
            }
        }
    }

    private func unregisterAllDeviceListeners() {
        for deviceID in monitoredDevices {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main) { _, _ in }
        }
        monitoredDevices = []
    }

    // MARK: - Device List Change

    private func registerDeviceListChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }
        deviceListChangedRegistered = (status == noErr)
    }

    private func unregisterDeviceListChangeListener() {
        guard deviceListChangedRegistered else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
        ) { _, _ in }
        deviceListChangedRegistered = false
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAllDevices()
            }
        }
    }

    // MARK: - State Check

    private func isDeviceRunning(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &isRunning)
        return status == noErr && isRunning != 0
    }

    private func checkAllDevices() {
        let anyActive = monitoredDevices.contains { isDeviceRunning($0) }

        if anyActive && !micInUse {
            micInUse = true
            sessionStartTime = Date()
            sessionApp = frontmostAppName
            ongoingSessionSeconds = 0
            startTimers()
        } else if !anyActive && micInUse {
            stopTimers()
            endSession()
        }
    }

    private func endSession() {
        if let start = sessionStartTime {
            let duration = Date().timeIntervalSince(start)
            let app = sessionApp ?? frontmostAppName
            store.addTalkDuration(duration, app: app)
        }
        micInUse = false
        sessionStartTime = nil
        sessionApp = nil
        ongoingSessionSeconds = 0
    }

    // MARK: - Timers

    private func startTimers() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.sessionStartTime else { return }
                self.ongoingSessionSeconds = Date().timeIntervalSince(start)
            }
        }

        flushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushOngoingSession()
            }
        }
    }

    private func stopTimers() {
        displayTimer?.invalidate()
        displayTimer = nil
        flushTimer?.invalidate()
        flushTimer = nil
    }

    private func flushOngoingSession() {
        guard micInUse, let start = sessionStartTime else { return }
        let now = Date()
        let duration = now.timeIntervalSince(start)
        let app = sessionApp ?? frontmostAppName
        store.addTalkDuration(duration, app: app)
        sessionStartTime = now
        ongoingSessionSeconds = 0
    }
}
