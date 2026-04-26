import SwiftUI

struct CardHeader: View {
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.sweeplyTextSub)
                }
            }
            Spacer()
            if let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text("View all".translated())
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.sweeplyTextSub)
                }
                .buttonStyle(.plain)
            }
        }
    }
}


