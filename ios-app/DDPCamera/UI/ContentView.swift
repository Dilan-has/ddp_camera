import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var vm = StreamViewModel()

    var body: some View {
        ZStack {
            // Preview camara de fondo
            CameraPreviewView(session: vm.cameraSession)
                .ignoresSafeArea()

            VStack {
                // Panel superior — estado
                HStack {
                    Circle()
                        .fill(vm.isStreaming ? Color.red : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(vm.isStreaming ? "LIVE" : "IDLE")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                    Spacer()
                    Text(vm.stats)
                        .font(.caption2.monospaced())
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(8)
                .background(.black.opacity(0.5))

                Spacer()

                // Panel inferior — configuracion
                VStack(spacing: 12) {
                    HStack {
                        Text("IP").foregroundColor(.white).frame(width: 30)
                        TextField("192.168.1.x", text: $vm.host)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                    }

                    HStack {
                        Text("Port").foregroundColor(.white).frame(width: 30)
                        TextField("5151", text: $vm.port)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                    }

                    HStack {
                        Text("Quality").foregroundColor(.white).frame(width: 50)
                        Slider(value: $vm.bitrateMultiplier, in: 0.25...1.0, step: 0.25)
                        Text("\(Int(vm.bitrateMultiplier * 100))%")
                            .foregroundColor(.white)
                            .frame(width: 40)
                    }

                    Picker("Resolution", selection: $vm.resolution) {
                        Text("4K").tag(Resolution.uhd4k)
                        Text("1080p").tag(Resolution.hd1080)
                        Text("720p").tag(Resolution.hd720)
                    }
                    .pickerStyle(.segmented)

                    Button {
                        vm.isStreaming ? vm.stopStream() : vm.startStream()
                    } label: {
                        Text(vm.isStreaming ? "Stop" : "Start Streaming")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(vm.isStreaming ? Color.red : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
                .background(.black.opacity(0.6))
                .cornerRadius(16)
                .padding()
            }
        }
        .onAppear { vm.setup() }
        .preferredColorScheme(.dark)
    }
}
