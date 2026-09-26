import AVFAudio
import HealthKit
import Speech
import UserNotifications

/// The system permissions the app asks for, and the one place that asks.
///
/// Asking is always preceded by a screen that says why (the wizard's priming
/// steps). iOS shows each system prompt once; a refusal can only be undone in
/// the Settings app, so a cold prompt wastes the only chance.
enum Permissions {
    /// What Khepri reads from Apple Health. Phase 4 syncs these to the server
    /// so the coach sees them alongside Strava.
    static let healthReadTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.stepCount),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.heartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.bodyMass),
        HKCategoryType(.sleepAnalysis),
        // My Day: rings, daylight, and what other apps logged about food.
        HKQuantityType(.appleExerciseTime),
        HKCategoryType(.appleStandHour),
        HKQuantityType(.timeInDaylight),
        HKQuantityType(.dietaryWater),
        HKQuantityType(.dietaryCaffeine),
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.dietaryFatTotal),
        HKQuantityType(.bodyMassIndex),
        HKQuantityType(.bloodPressureSystolic),
        HKQuantityType(.bloodPressureDiastolic),
        HKQuantityType(.dietaryVitaminA),
        HKQuantityType(.dietaryVitaminC),
        HKQuantityType(.dietaryVitaminD),
    ]

    /// What Khepri writes: workouts finished in the app.
    static let healthShareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
    ]

    /// Shows the Health sheet. HealthKit never reveals whether reading was
    /// allowed, only that the sheet was answered, so there is nothing useful
    /// to return: code that reads simply gets no samples when refused.
    static func requestHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await HKHealthStore().requestAuthorization(toShare: healthShareTypes, read: healthReadTypes)
    }

    /// Shows the notification prompt. Returns whether alerts are allowed.
    @discardableResult
    static func requestNotifications() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        // Allowed now, so nudges can come from the server too.
        if granted { await PushRegistration.registerIfAllowed() }
        return granted
    }

    enum Access { case undetermined, granted, denied }

    /// Dictation needs the microphone and speech recognition. Denied if
    /// either was refused: only the Settings app can change that.
    static var dictation: Access {
        let microphone = AVAudioApplication.shared.recordPermission
        let speech = SFSpeechRecognizer.authorizationStatus()
        if microphone == .denied || speech == .denied || speech == .restricted { return .denied }
        if microphone == .granted && speech == .authorized { return .granted }
        return .undetermined
    }

    /// Shows the microphone prompt, then the speech recognition prompt.
    /// Returns whether both were allowed.
    static func requestDictation() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        let speech = await withCheckedContinuation { continuation in
            // Answered on a background queue, so the closure must not be main-actor.
            SFSpeechRecognizer.requestAuthorization { @Sendable status in continuation.resume(returning: status) }
        }
        return speech == .authorized
    }
}
