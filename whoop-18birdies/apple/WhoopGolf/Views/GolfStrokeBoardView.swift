import MapKit
import SwiftUI

/// Phone stroke board: path score, explanation, swing-to-swing yards, and a map.
struct GolfStrokeBoardView: View {
    let rows: [GolfStrokePresentation.Row]
    var title: String = "STROKES"
    var emptyDetail: String =
        "Accepted Watch or WHOOP swings appear here with path score, explanation, and GPS displacement yards."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Color.golfMist)
                Spacer()
                Text("\(rows.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.golfLime)
            }

            if rows.isEmpty {
                Text(emptyDetail)
                    .font(.subheadline)
                    .foregroundStyle(Color.golfMist)
            } else {
                if hasMapPoints {
                    StrokeMapView(rows: rows)
                        .frame(height: 168)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                ForEach(rows.suffix(12).reversed()) { row in
                    StrokeBoardRowView(row: row)
                    if row.id != rows.suffix(12).reversed().last?.id {
                        Divider().overlay(.white.opacity(0.08))
                    }
                }
            }
        }
    }

    private var hasMapPoints: Bool {
        rows.contains { $0.coordinate != nil }
    }
}

private struct StrokeBoardRowView: View {
    let row: GolfStrokePresentation.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("#\(row.sequence)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.golfLime)
                if let hole = row.hole {
                    Text("H\(hole)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.golfMist)
                }
                Text(row.score.scoreHeadline)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(row.capturedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Color.golfMist)
            }

            Text(row.score.explanation)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let club = row.clubLabel {
                    Text(club)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.golfLime.opacity(0.18), in: Capsule())
                }
                if let ball = row.ballStartLabel {
                    Text(ball)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                if let attack = row.attackFeelLabel {
                    Text(attack)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.08), in: Capsule())
                }
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.golfSand)

            if let detail = row.ballStartDetail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Color.golfMist)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Label(row.yardsLine, systemImage: "ruler")
                if let hr = row.heartRateBPM {
                    Label("\(hr) bpm", systemImage: "heart.fill")
                }
                Label(String(format: "%.1f g", row.peakG), systemImage: "gyroscope")
                Text(row.provenanceLabel)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.08), in: Capsule())
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.golfMist)
            .lineLimit(2)

            Text(row.score.tip.missAdvice)
                .font(.caption2)
                .foregroundStyle(Color.golfSand.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)

            Text("Next · \(row.score.tip.postSwing)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.golfLime.opacity(0.9))
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StrokeMapView: View {
    let rows: [GolfStrokePresentation.Row]

    var body: some View {
        Map {
            ForEach(mapped) { item in
                Annotation("#\(item.sequence)", coordinate: item.coordinate) {
                    ZStack {
                        Circle()
                            .fill(Color.golfLime.opacity(0.9))
                            .frame(width: 18, height: 18)
                        Text("\(item.sequence)")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(Color.golfInk)
                    }
                }
            }
            if mapped.count >= 2 {
                MapPolyline(coordinates: mapped.map(\.coordinate))
                    .stroke(Color.golfLime.opacity(0.55), lineWidth: 2.5)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .disabled(true)
        .accessibilityLabel("Stroke map")
        .accessibilityValue("\(mapped.count) located swings")
    }

    private var mapped: [MappedStroke] {
        rows.compactMap { row in
            guard let coordinate = row.coordinate else { return nil }
            return MappedStroke(id: row.id, sequence: row.sequence, coordinate: coordinate)
        }
    }

    private struct MappedStroke: Identifiable {
        let id: UUID
        let sequence: Int
        let coordinate: CLLocationCoordinate2D
    }
}
