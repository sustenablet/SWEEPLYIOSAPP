import SwiftUI

struct SectionCard<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        content
            .padding(16)
            .background(Color.sweeplySurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sweeplyBorder, lineWidth: 1)
            )
    }
}

#Preview {
    ZStack {
        Color.sweeplyBackground.ignoresSafeArea()
        SectionCard {
            Text("Sample Card Content".translated())
                .font(.headline)
        }
        .padding()
    }
}
