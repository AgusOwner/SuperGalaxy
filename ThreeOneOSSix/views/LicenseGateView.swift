import SwiftUI
import UIKit

enum LicenseStore {
    private static let key = "argent.license.validated"

    static var isValidated: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

struct LicenseGateView: View {
    var onUnlocked: () -> Void

    @State private var keyText: String = ""
    @State private var isChecking = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Image("GalaxyXLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)

                Text("GALAXYX")
                    .font(.system(size: 28, weight: .heavy, design: .default))
                    .foregroundStyle(.white)
                    .tracking(4)

                VStack(spacing: 14) {
                    HStack {
                        Image("GalaxyXLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        SecureField("Ingresa tu licencia", text: $keyText)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .foregroundStyle(.white)
                    }
                    .padding()
                    .background(AppTheme.consoleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.accent)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        validate()
                    } label: {
                        HStack {
                            if isChecking {
                                ProgressView().tint(.white)
                            } else {
                                Text("Desbloquear")
                                    .fontWeight(.bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(keyText.isEmpty || isChecking)

                    Button {
                        openDiscord()
                    } label: {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                            Text("DISCORD")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.consoleBackground)
                        .foregroundStyle(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(AppTheme.accent.opacity(0.5), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
    }

    private func openDiscord() {
        guard let url = URL(string: "https://discord.gg/ynGNUv5DZe") else { return }
        UIApplication.shared.open(url)
    }

    private func validate() {
        errorMessage = nil
        isChecking = true
        Task {
            do {
                try await KeyAuthService.license(key: keyText)
                await MainActor.run {
                    isChecking = false
                    LicenseStore.isValidated = true
                    onUnlocked()
                }
            } catch {
                await MainActor.run {
                    isChecking = false
                    // TEMP diagnostics: shows the raw KeyAuth error so we can
                    // tell apart a network failure, an API rejection and a
                    // decoding error. Remove once licensing is confirmed working.
                    switch error {
                    case KeyAuthError.network(let detail):
                        errorMessage = "Red: \(detail)"
                    case KeyAuthError.api(let detail):
                        errorMessage = "KeyAuth: \(detail)"
                    case KeyAuthError.decoding:
                        errorMessage = "Respuesta no válida de KeyAuth (decoding)"
                    default:
                        errorMessage = "Error desconocido: \(error)"
                    }
                }
            }
        }
    }
}
