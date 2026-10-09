import SwiftUI

/// Credits the licences of assets the app ships require.
struct Acknowledgements: View {
    var body: some View {
        List {
            Section {
                Text("The body figure is cut from anatomical data from Z-Anatomy, via hpfrei/body-anatomy-3d-viewer, licensed CC BY-SA 4.0, fitted to Human Body Base Mesh Male by ferrumiron6, licensed CC BY 4.0. The figure is licensed CC BY-SA 4.0.")
                Link("Z-Anatomy", destination: URL(string: "https://www.z-anatomy.com/")!)
                Link("hpfrei/body-anatomy-3d-viewer", destination: URL(string: "https://github.com/hpfrei/body-anatomy-3d-viewer")!)
                Link("Human Body Base Mesh Male", destination: URL(string: "https://sketchfab.com/3d-models/human-body-base-mesh-male-3678451d8ccb435e833f8a10729c09f5")!)
                Link("CC BY-SA 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
            } header: {
                Text("Body figure")
            }
        }
        .navigationTitle("Acknowledgements")
    }
}
