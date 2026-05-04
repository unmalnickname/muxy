import Foundation
import Testing

@testable import Muxy

@Suite("AttentionState")
@MainActor
struct AttentionStateTests {
    @Test("alertColor is nil by default")
    func alertColorNilByDefault() {
        let state = AttentionState()
        #expect(state.alertColor == nil)
        #expect(!state.hasAlert)
    }

    @Test("alertColor returns agent color after agent completion")
    func alertColorAfterAgentCompletion() {
        let state = AttentionState()
        state.agentCompleted()
        #expect(state.alertColor != nil)
        #expect(state.hasAlert)
    }

    @Test("alertColor returns idle color when idle")
    func alertColorWhenIdle() {
        let state = AttentionState()
        state.setIdle(true)
        #expect(state.alertColor != nil)
        #expect(state.hasAlert)
    }

    @Test("agent alert takes priority over idle alert")
    func agentPriorityOverIdle() {
        let state = AttentionState()
        state.setIdle(true)
        state.agentCompleted()
        #expect(state.alertColor != nil)
    }

    @Test("alertColor clears after setIdle(false)")
    func alertColorAfterClear() {
        let state = AttentionState()
        state.setIdle(true)
        #expect(state.alertColor != nil)
        state.setIdle(false)
        #expect(state.alertColor == nil)
    }

    @Test("hasAlert mirrors alertColor")
    func hasAlertMirrorsAlertColor() {
        let state = AttentionState()
        #expect(state.hasAlert == (state.alertColor != nil))
        state.setIdle(true)
        #expect(state.hasAlert == (state.alertColor != nil))
        state.setIdle(false)
        #expect(state.hasAlert == (state.alertColor != nil))
    }

    @Test("setIdle toggles correctly")
    func setIdleToggles() {
        let state = AttentionState()
        #expect(!state.isIdle)
        state.setIdle(true)
        #expect(state.isIdle)
        state.setIdle(false)
        #expect(!state.isIdle)
    }

    @Test("setIdle skips redundant update")
    func setIdleSkipsRedundant() {
        let state = AttentionState()
        state.setIdle(false)
        state.setIdle(false)
        #expect(!state.isIdle)
    }

    @Test("reloadSettings bumps settingsVersion")
    func reloadSettingsBumpsVersion() {
        let state = AttentionState()
        let before = state.settingsVersion
        state.reloadSettings()
        #expect(state.settingsVersion == before + 1)
    }

    @Test("pulseDuration returns default for unknown setting")
    func pulseDurationDefault() {
        let state = AttentionState()
        let duration = state.pulseDuration
        #expect(duration == AttentionSettingsKeys.defaultPulseSpeed)
    }

    @Test("isIdle starts as false")
    func isIdleStartsFalse() {
        let state = AttentionState()
        #expect(!state.isIdle)
    }

    @Test("settingsVersion starts at 0")
    func settingsVersionStartsZero() {
        let state = AttentionState()
        #expect(state.settingsVersion == 0)
    }
}
