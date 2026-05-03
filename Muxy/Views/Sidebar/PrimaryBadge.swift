import SwiftUI

struct PrimaryBadge: View {
    var body: some View {
        Text("PRIMARY")
            .font(.system(size: 8, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(MuxyTheme.fgDim)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(MuxyTheme.surface, in: Capsule())
    }
}
