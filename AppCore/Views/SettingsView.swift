import SwiftUI

public struct SettingsView: View {
    @ObservedObject var vm: PortfolioViewModel
    @Environment(\.presentationMode) var presentationMode

    @State private var inputHost: String = ""
    @State private var inputPort: String = ""

    public init(vm: PortfolioViewModel) {
        self.vm = vm
        _inputHost = State(initialValue: vm.pcHost)
        _inputPort = State(initialValue: vm.pcPort)
    }

    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 16) {
                // Barra superior
                HStack {
                    Text("Conexión con tu PC")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top, 14)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Dirección de tu PC (en tu red WiFi):")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(white: 0.6))

                    HStack {
                        Image(systemName: "desktopcomputer")
                            .foregroundColor(.gray)
                        TextField("IP del PC (ej: 192.168.1.128)", text: $inputHost)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                            .keyboardType(.numbersAndPunctuation)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    .padding(10)
                    .background(Color(white: 0.12))
                    .cornerRadius(8)

                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.gray)
                        TextField("Puerto (ej: 8765)", text: $inputPort)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                            .keyboardType(.numberPad)
                    }
                    .padding(10)
                    .background(Color(white: 0.12))
                    .cornerRadius(8)
                }

                // Botón Guardar y Sincronizar
                Button(action: {
                    vm.saveConnectionSettings(host: inputHost, port: inputPort)
                    vm.performSync(isManual: true)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Guardar y Sincronizar")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.0, green: 0.7, blue: 0.7))
                    .foregroundColor(.black)
                    .cornerRadius(10)
                }

                Text("Asegúrate de tener encendido tu CryptoWidget en el PC y ambos dispositivos en la misma red WiFi.")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)

                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }
}
