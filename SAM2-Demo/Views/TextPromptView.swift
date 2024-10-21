import SwiftUI

struct TextPromptView: View {
    @State private var textPrompt: String = ""
    var onSubmit: (String) -> Void

    var body: some View {
        VStack {
            TextField("Enter text prompt", text: $textPrompt)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button(action: {
                onSubmit(textPrompt)
            }) {
                Text("Submit")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
}
