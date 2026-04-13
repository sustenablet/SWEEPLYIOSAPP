import SwiftUI
import MapKit

struct MapJobCard: View {
    let job: Job
    let onDirections: () -> Void
    let onDetails: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(job.clientName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.sweeplyNavy)
                        
                        StatusBadge(status: job.status)
                    }
                    
                    Text(job.address)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.sweeplyTextSub)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Circle()
                        .fill(Color.sweeplyBackground)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.sweeplyTextSub)
                        )
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: 12) {
                InfoChip(icon: "clock.fill", text: job.date.formatted(.dateTime.hour().minute()))
                InfoChip(icon: "hourglass", text: "\(Int(job.duration)) hr")
                InfoChip(icon: "tag.fill", text: job.price.currencyWithoutTrailingZeros)
                
                if job.isRecurring {
                    InfoChip(icon: "arrow.triangle.2.circlepath", text: "Recurring", color: .sweeplyAccent)
                }
            }
            
            HStack(spacing: 12) {
                Button(action: onDirections) {
                    HStack {
                        Image(systemName: "arrow.turn.up.right")
                        Text("Directions")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.sweeplyNavy)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                
                Button(action: onDetails) {
                    Text("View Job")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.sweeplyNavy)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.sweeplySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.sweeplyBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(Color.sweeplySurface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 15, x: 0, y: 5)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

private struct InfoChip: View {
    let icon: String
    let text: String
    var color: Color = Color.sweeplyTextSub
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}
