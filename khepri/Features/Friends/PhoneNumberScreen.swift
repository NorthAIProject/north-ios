import NorthAPI
import NorthKit
import SwiftUI

/// Your phone number, proved with a texted code, so friends who have it in
/// their contacts can find you. Nobody is ever shown it.
struct PhoneNumberScreen: View {
    var service: FriendsServicing = FriendsService()
    /// Shared with Friends, so its row is current on the way back.
    @Binding var status: PhoneStatus?

    @State private var region = PhoneNumberScreen.homeRegion
    @State private var number = ""
    @State private var code = ""
    @State private var changing = false
    @State private var fieldErrors: [String: String] = [:]
    @State private var error: String?
    @State private var working = false
    @State private var confirmingRemove = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        Form {
            if let status {
                if !status.pending.isEmpty {
                    entering(code: status.pending)
                } else if !status.number.isEmpty && !changing {
                    verified(status)
                } else if status.configured {
                    entering(number: status)
                } else {
                    Text("Adding a phone number is not available right now.").foregroundStyle(.secondary)
                }
            } else if error == nil {
                ProgressView()
            }
            if let error { ErrorRow(error) }
        }
        .navigationTitle("Phone Number")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog("Remove your phone number?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove Number", role: .destructive) { Task { await run { try await service.removePhone(); return try await service.phone() } } }
        } message: {
            Text("Friends stop finding you by it. You can add it again any time.")
        }
    }

    private func entering(number current: PhoneStatus) -> some View {
        Group {
            Section {
                Picker("Country", selection: $region) {
                    ForEach(Self.countries, id: \.region) { country in
                        Text("\(country.name) +\(country.code.digits)").tag(Optional(country.region))
                    }
                    Text("Other: type the number with +").tag(String?.none)
                }
                TextField("Phone number", text: $number)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .accessibilityIdentifier("phone.number")
                if let message = fieldErrors["phone"] ?? fieldErrors["countryCode"] ?? fieldErrors["country"] {
                    ErrorRow(message)
                }
            } footer: {
                Text("Friends who have your number in their contacts can find you. Your number is never shown to anyone.")
            }
            Section {
                Button("Send Code") { Task { await sendCode() } }
                    .disabled(working || number.trimmingCharacters(in: .whitespaces).isEmpty)
                if changing {
                    Button("Keep \(current.number)") { changing = false; fieldErrors = [:] }
                }
            }
        }
    }

    private func entering(code pending: String) -> some View {
        Group {
            Section {
                TextField("6-digit code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($codeFocused)
                    .accessibilityIdentifier("phone.code")
                    .onChange(of: code) { _, now in
                        let digits = String(now.filter(\.isNumber).prefix(6))
                        if digits != now { code = digits }
                        if digits.count == 6, !working { Task { await checkCode() } }
                    }
                if let message = fieldErrors["code"] { ErrorRow(message) }
            } header: {
                Text("Code sent to \(pending)")
            } footer: {
                Text("The code works for ten minutes.")
            }
            Section {
                Button("Verify") { Task { await checkCode() } }
                    .disabled(working || code.count < 6)
                Button("Send a New Code") {
                    Task { await run { try await service.startPhoneVerification(pending, countryCode: nil) } }
                }
                .disabled(working)
                Button("Use a Different Number") {
                    Task { await run { try await service.cancelPhoneVerification(); return try await service.phone() } }
                }
                .disabled(working)
            }
        }
        .onAppear { codeFocused = true }
    }

    private func verified(_ status: PhoneStatus) -> some View {
        Group {
            Section {
                LabeledContent("Number", value: status.number)
                if let at = status.verifiedAt {
                    LabeledContent("Verified", value: at.formatted(date: .abbreviated, time: .omitted))
                }
            } footer: {
                Text("Friends who have your number in their contacts can find you. Your number is never shown to anyone.")
            }
            Section {
                if status.configured {
                    Button("Change Number") { changing = true; number = "" }
                }
                Button("Remove Number", role: .destructive) { confirmingRemove = true }
                    .disabled(working)
            }
        }
    }

    private func load() async {
        do { status = try await service.phone(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func sendCode() async {
        let typed = number.trimmingCharacters(in: .whitespaces)
        let international = typed.hasPrefix("+") || typed.hasPrefix("00")
        let countryCode = international ? nil : region.flatMap { PhoneNumbers.callingCode(region: $0)?.digits }
        await run { try await service.startPhoneVerification(typed, countryCode: countryCode) }
    }

    private func checkCode() async {
        await run { try await service.checkPhoneCode(code) }
    }

    /// Runs one step and shows where it left things: a field error beside its
    /// field, a refusal such as too many codes above the form.
    private func run(_ step: () async throws -> PhoneStatus) async {
        working = true
        defer { working = false }
        do {
            let next = try await step()
            if next.pending.isEmpty { changing = false }
            if next.pending != status?.pending { code = "" }
            status = next
            fieldErrors = [:]
            error = nil
        } catch let APIError.fieldValidation(message, fields) {
            fieldErrors = fields
            error = fields.isEmpty ? message : nil
            if fields["code"] != nil { code = "" }
        } catch {
            fieldErrors = [:]
            self.error = error.localizedDescription
        }
    }
}

extension PhoneNumberScreen {
    /// This iPhone's region when the picker knows its calling code.
    static var homeRegion: String? {
        Locale.current.region.map(\.identifier).flatMap { PhoneNumbers.callingCodes[$0] == nil ? nil : $0 }
    }

    /// Every region with a known calling code, by name in the phone's language.
    static let countries: [(region: String, name: String, code: CallingCode)] = PhoneNumbers.callingCodes
        .map { (region: $0.key, name: Locale.current.localizedString(forRegionCode: $0.key) ?? $0.key, code: $0.value) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}
