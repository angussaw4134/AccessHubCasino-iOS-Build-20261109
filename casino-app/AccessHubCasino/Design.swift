import SwiftUI
import UIKit

enum AH {
    static let background = Color(red: 11/255, green: 15/255, blue: 20/255)
    static let panel = Color(red: 18/255, green: 25/255, blue: 32/255)
    static let raised = Color(red: 24/255, green: 34/255, blue: 42/255)
    static let emerald = Color(red: 0, green: 213/255, blue: 160/255)
    static let text = Color(red: 239/255, green: 245/255, blue: 242/255)
    static let muted = Color(red: 149/255, green: 164/255, blue: 172/255)
    static let gold = Color(red: 235/255, green: 201/255, blue: 132/255)
    static let danger = Color(red: 252/255, green: 124/255, blue: 135/255)
}

struct Panel<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(AH.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.065)))
    }
}

struct PrimaryButton: ButtonStyle {
    var secondary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 15, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 14)
            .foregroundStyle(secondary ? AH.text : AH.background)
            .background(secondary ? AH.raised : AH.emerald, in: RoundedRectangle(cornerRadius: 14))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SectionTitle: View {
    let title: String
    var caption: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(AH.text)
            if let caption { Text(caption).font(.subheadline).foregroundStyle(AH.muted).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Brand: View {
    var compact = false
    var casino = false
    var body: some View {
        HStack(spacing: 10) {
            Group {
                if UIImage(named: "AHMonogram") != nil { Image("AHMonogram").resizable().scaledToFit() }
                else { Text("AH").font(.system(size: 25, weight: .medium, design: .serif)).tracking(-4).foregroundStyle(AH.emerald) }
            }.frame(width: compact ? 32 : 44, height: compact ? 32 : 44)
            if !compact {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACCESSHUB").font(.system(size: 17, weight: .semibold)).tracking(2.3)
                    if casino { Text("C A S I N O").font(.system(size: 9, weight: .medium)).foregroundStyle(AH.muted) }
                }
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(casino ? "AccessHub Casino" : "AccessHub")
    }
}

struct CreditBalance: View {
    let units: Double
    var large = false
    @EnvironmentObject var store: CasinoStore
    var body: some View {
        VStack(alignment: .leading, spacing: large ? 9 : 3) {
            Text("ACCESS HUB CREDITS").font(.system(size: large ? 10 : 9, weight: .semibold)).tracking(1.7).foregroundStyle(AH.muted)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(Credits.format(units)).font(.system(size: large ? 36 : 19, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: units)).animation(store.reducedMotion ? nil : .easeOut(duration: 0.45), value: units)
                if large { Image(systemName: "sparkle").font(.body).foregroundStyle(AH.emerald) }
            }
        }.accessibilityElement(children: .combine).accessibilityValue(Credits.format(units))
    }
}

struct GameArtwork: View {
    let game: CasinoGame
    var body: some View {
        GeometryReader { geometry in
          ZStack {
            AH.panel
            if UIImage(named: game.art) != nil { Image(game.art).resizable().scaledToFill().frame(width:geometry.size.width,height:geometry.size.height).clipped() }
            else {
                RadialGradient(colors: [AH.emerald.opacity(0.2), AH.panel], center: .center, startRadius: 0, endRadius: 240)
                Group {
                    switch game {
                    case .crash: OrbitArt()
                    case .blackjack: HStack(spacing: -28) { PlayingCard(card: .object(["rank": .string("A"), "suit": .string("spades")])).rotationEffect(.degrees(-14)); PlayingCard(card: .object(["rank": .string("K"), "suit": .string("hearts")])).rotationEffect(.degrees(10)) }.frame(width: 160, height: 130)
                    case .mines: GemArt().frame(width: 110, height: 125)
                    case .slots: HStack { SlotSymbol(symbol: "crown"); SlotSymbol(symbol: "gem"); SlotSymbol(symbol: "seven") }.frame(width: 220, height: 90)
                    }
                }
            }
          }
        }.clipped().accessibilityHidden(true)
    }
}

struct OrbitArt: View {
    var body: some View {
        ZStack {
            ForEach(0..<4) { i in Circle().stroke(AH.emerald.opacity(0.08 + Double(i) * 0.04), lineWidth: 1).frame(width: CGFloat(90 + i * 40)).rotation3DEffect(.degrees(60), axis: (x: 1, y: 0, z: 0)) }
            GemArt().frame(width: 60, height: 80).rotationEffect(.degrees(30))
        }
    }
}

struct GemArt: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width; let h = g.size.height
            ZStack {
                Path { p in p.move(to: CGPoint(x: w*0.25,y: 0)); p.addLine(to: CGPoint(x:w*0.75,y:0)); p.addLine(to:CGPoint(x:w,y:h*0.32)); p.addLine(to:CGPoint(x:w*0.5,y:h)); p.addLine(to:CGPoint(x:0,y:h*0.32)); p.closeSubpath() }.fill(LinearGradient(colors:[Color(red:0.4,green:1,blue:0.8),AH.emerald,Color(red:0,green:0.26,blue:0.23)], startPoint:.topLeading,endPoint:.bottomTrailing))
                Path { p in p.move(to:CGPoint(x:0,y:h*0.32)); p.addLine(to:CGPoint(x:w,y:h*0.32)); p.move(to:CGPoint(x:w*0.25,y:0)); p.addLine(to:CGPoint(x:w*0.5,y:h)); p.addLine(to:CGPoint(x:w*0.75,y:0)); p.move(to:CGPoint(x:w*0.25,y:0)); p.addLine(to:CGPoint(x:w*0.75,y:0)) }.stroke(.white.opacity(0.55),lineWidth:1)
            }
        }
    }
}

struct MineArt: View {
    var body: some View {
        ZStack {
            ForEach(0..<8) { i in RoundedRectangle(cornerRadius: 3).fill(AH.danger).frame(width: 6, height: 42).rotationEffect(.degrees(Double(i) * 45)) }
            Circle().fill(LinearGradient(colors: [.gray, AH.raised, .black], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 32, height: 32)
            Circle().fill(AH.danger).frame(width: 7,height:7).offset(x:-5,y:-6)
        }
    }
}

struct SlotSymbol: View {
    let symbol: String
    private var asset: String { "Symbol" + symbol.capitalized }
    var body: some View {
        Group {
            if UIImage(named: asset) != nil { Image(asset).resizable().scaledToFit() }
            else if symbol == "gem" { GemArt().padding(8) }
            else if symbol == "seven" { Text("7").font(.system(size: 46, weight: .black, design: .serif)).foregroundStyle(AH.emerald).shadow(color: AH.emerald.opacity(0.4), radius: 8) }
            else {
                Canvas { context, size in
                    let w = size.width; let h = size.height
                    var p = Path()
                    if symbol == "crown" {
                        p.move(to: CGPoint(x:w*0.15,y:h*0.3)); p.addLine(to:CGPoint(x:w*0.3,y:h*0.5)); p.addLine(to:CGPoint(x:w*0.5,y:h*0.16)); p.addLine(to:CGPoint(x:w*0.7,y:h*0.5)); p.addLine(to:CGPoint(x:w*0.85,y:h*0.3)); p.addLine(to:CGPoint(x:w*0.75,y:h*0.8)); p.addLine(to:CGPoint(x:w*0.25,y:h*0.8)); p.closeSubpath()
                    } else if symbol == "bell" {
                        p.move(to:CGPoint(x:w*0.2,y:h*0.75)); p.addQuadCurve(to:CGPoint(x:w*0.35,y:h*0.35),control:CGPoint(x:w*0.34,y:h*0.65)); p.addQuadCurve(to:CGPoint(x:w*0.65,y:h*0.35),control:CGPoint(x:w*0.5,y:0)); p.addQuadCurve(to:CGPoint(x:w*0.8,y:h*0.75),control:CGPoint(x:w*0.66,y:h*0.65)); p.closeSubpath(); p.addEllipse(in:CGRect(x:w*0.42,y:h*0.77,width:w*0.16,height:h*0.1))
                    } else {
                        p.addEllipse(in:CGRect(x:w*0.12,y:h*0.48,width:w*0.37,height:h*0.37)); p.addEllipse(in:CGRect(x:w*0.51,y:h*0.42,width:w*0.37,height:h*0.37))
                    }
                    context.fill(p,with:.linearGradient(Gradient(colors: symbol == "cherry" ? [AH.danger,Color(red:0.5,green:0.08,blue:0.2)] : [Color.white,AH.gold,Color.brown]), startPoint:.zero,endPoint:CGPoint(x:w,y:h)))
                    if symbol == "cherry" {
                        var stem = Path(); stem.move(to:CGPoint(x:w*0.3,y:h*0.5)); stem.addQuadCurve(to:CGPoint(x:w*0.58,y:h*0.15),control:CGPoint(x:w*0.45,y:h*0.4)); stem.addQuadCurve(to:CGPoint(x:w*0.7,y:h*0.45),control:CGPoint(x:w*0.72,y:h*0.2)); context.stroke(stem,with:.color(AH.emerald),lineWidth:3)
                    }
                }
            }
        }.accessibilityLabel(symbol.capitalized)
    }
}

struct PlayingCard: View {
    let card: JSONValue
    var back = "classic"
    var body: some View {
        GeometryReader { g in
            let red = ["hearts", "diamonds"].contains(card["suit"].string)
            let suit = ["hearts":"♥", "diamonds":"♦", "spades":"♠", "clubs":"♣"][card["suit"].string] ?? "♠"
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(card.exists ? Color(red:0.97,green:0.97,blue:0.92) : AH.raised)
                if card.exists {
                    VStack {
                        HStack(alignment:.top) { VStack(spacing:0) { Text(card["rank"].string).font(.system(size:max(12,g.size.width*0.23),weight:.bold,design:.serif)); Text(suit).font(.system(size:max(10,g.size.width*0.19))) }; Spacer() }
                        Spacer(minLength:0)
                        CardFace(rank:card["rank"].string,suit:suit,red:red)
                            .frame(maxWidth:.infinity,maxHeight:.infinity)
                        Spacer(minLength:0)
                        HStack { Spacer(); Text(card["rank"].string + suit).font(.system(size:max(10,g.size.width*0.18),weight:.bold,design:.serif)).rotationEffect(.degrees(180)) }
                    }.padding(max(5,g.size.width*0.09)).foregroundStyle(red ? Color(red:0.73,green:0.12,blue:0.23) : Color(red:0.08,green:0.14,blue:0.17))
                } else if back.hasPrefix("hub|") {
                    HubCardBack(specification:back)
                } else {
                    RoundedRectangle(cornerRadius:5).strokeBorder(back == "royal" ? AH.gold : AH.emerald.opacity(0.8),lineWidth:1).padding(5)
                    VStack(spacing:3) { ForEach(0..<5) { _ in HStack(spacing:4) { ForEach(0..<3) { _ in Text(back == "circuit" ? "+" : "◆").font(.system(size:11)).foregroundStyle(back == "royal" ? AH.gold.opacity(0.7) : AH.emerald.opacity(0.5)) } } } }
                    Text("AH").font(.system(size:g.size.width*0.28,weight:.bold,design:.serif)).foregroundStyle(AH.text).padding(7).background(AH.panel,in:RoundedRectangle(cornerRadius:6))
                }
            }.overlay(RoundedRectangle(cornerRadius:8).strokeBorder(.white.opacity(0.2))).shadow(color:.black.opacity(0.25),radius:5,y:4)
        }.aspectRatio(0.7,contentMode:.fit)
            .accessibilityLabel(card.exists ? "\(card["rank"].string) of \(card["suit"].string)" : "Face down card")
    }
}

/// Original vector card faces. Number cards use their actual pip count;
/// court cards use mirrored illustrated figures instead of interface icons.
struct CardFace: View {
    let rank: String
    let suit: String
    let red: Bool
    private var ink: Color { red ? Color(red:0.73,green:0.12,blue:0.23) : Color(red:0.08,green:0.14,blue:0.17) }
    var body: some View {
        GeometryReader { geometry in
            if ["J","Q","K"].contains(rank) {
                ZStack {
                    RoundedRectangle(cornerRadius:3).stroke(ink.opacity(0.35),lineWidth:0.6)
                    CourtFigure(rank:rank,ink:ink).frame(height:geometry.size.height*0.56).frame(maxHeight:.infinity,alignment:.top)
                    CourtFigure(rank:rank,ink:ink).frame(height:geometry.size.height*0.56).rotationEffect(.degrees(180)).frame(maxHeight:.infinity,alignment:.bottom)
                    Text(suit).font(.system(size:geometry.size.width*0.24)).foregroundStyle(ink).padding(2).background(Color(red:0.97,green:0.97,blue:0.92),in:Circle())
                }
            } else if rank == "A" {
                Text(suit).font(.system(size:min(geometry.size.width*0.65,geometry.size.height))).foregroundStyle(ink).frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                let positions = pips(Int(rank) ?? 1)
                ForEach(Array(positions.enumerated()),id:\.offset) { _,point in
                    Text(suit).font(.system(size:min(geometry.size.width*0.27,geometry.size.height*0.27)))
                        .foregroundStyle(ink).rotationEffect(.degrees(point.y > 0.5 ? 180 : 0))
                        .position(x:geometry.size.width*point.x,y:geometry.size.height*point.y)
                }
            }
        }.accessibilityHidden(true)
    }
    private func pips(_ count: Int) -> [CGPoint] {
        func point(_ x:Double,_ y:Double) -> CGPoint { CGPoint(x:x,y:y) }
        switch count {
        case 2:return [point(0.5,0.15),point(0.5,0.85)]
        case 3:return [point(0.5,0.15),point(0.5,0.5),point(0.5,0.85)]
        case 4:return [point(0.25,0.15),point(0.75,0.15),point(0.25,0.85),point(0.75,0.85)]
        case 5:return pips(4)+[point(0.5,0.5)]
        case 6:return pips(4)+[point(0.25,0.5),point(0.75,0.5)]
        case 7:return pips(6)+[point(0.5,0.33)]
        case 8:return pips(6)+[point(0.5,0.33),point(0.5,0.67)]
        case 9:return [0.12,0.37,0.63,0.88].flatMap { [point(0.25,$0),point(0.75,$0)] }+[point(0.5,0.5)]
        case 10:return [0.1,0.36,0.64,0.9].flatMap { [point(0.25,$0),point(0.75,$0)] }+[point(0.5,0.23),point(0.5,0.77)]
        default:return [point(0.5,0.5)]
        }
    }
}

struct CourtFigure: View {
    let rank: String
    let ink: Color
    var body: some View {
        Canvas { context,size in
            let w=size.width,h=size.height
            var robe=Path()
            robe.move(to:CGPoint(x:w*0.15,y:h));robe.addLine(to:CGPoint(x:w*0.23,y:h*0.66));robe.addLine(to:CGPoint(x:w*0.5,y:h*0.48));robe.addLine(to:CGPoint(x:w*0.77,y:h*0.66));robe.addLine(to:CGPoint(x:w*0.85,y:h));robe.closeSubpath()
            context.fill(robe,with:.color(ink))
            var trim=Path();trim.move(to:CGPoint(x:w*0.26,y:h*0.69));trim.addLine(to:CGPoint(x:w*0.5,y:h));trim.addLine(to:CGPoint(x:w*0.74,y:h*0.69))
            context.stroke(trim,with:.color(AH.gold),lineWidth:1.5)
            let head=Path(ellipseIn:CGRect(x:w*0.34,y:h*0.2,width:w*0.32,height:h*0.44))
            context.fill(head,with:.color(Color(red:0.9,green:0.73,blue:0.5)))
            var crown=Path();crown.move(to:CGPoint(x:w*0.29,y:h*0.27));crown.addLine(to:CGPoint(x:w*0.27,y:h*0.05));crown.addLine(to:CGPoint(x:w*0.42,y:h*0.15));crown.addLine(to:CGPoint(x:w*0.5,y:0));crown.addLine(to:CGPoint(x:w*0.58,y:h*0.15));crown.addLine(to:CGPoint(x:w*0.73,y:h*0.05));crown.addLine(to:CGPoint(x:w*0.71,y:h*0.27));crown.closeSubpath()
            context.fill(crown,with:.color(rank == "J" ? ink : AH.gold))
            var face=Path();face.move(to:CGPoint(x:w*0.55,y:h*0.33));face.addLine(to:CGPoint(x:w*0.55,y:h*0.45));face.addLine(to:CGPoint(x:w*0.48,y:h*0.45));face.move(to:CGPoint(x:w*0.44,y:h*0.54));face.addLine(to:CGPoint(x:w*0.58,y:h*0.54))
            context.stroke(face,with:.color(ink),lineWidth:0.6)
            context.fill(Path(ellipseIn:CGRect(x:w*0.43,y:h*0.34,width:1.1,height:1.1)),with:.color(ink))
            if rank == "Q" { context.fill(Path(ellipseIn:CGRect(x:w*0.31,y:h*0.46,width:w*0.06,height:w*0.06)),with:.color(AH.gold)) }
            if rank == "K" { var beard=Path();beard.move(to:CGPoint(x:w*0.36,y:h*0.52));beard.addLine(to:CGPoint(x:w*0.5,y:h*0.76));beard.addLine(to:CGPoint(x:w*0.64,y:h*0.52));beard.closeSubpath();context.fill(beard,with:.color(ink.opacity(0.8))) }
        }
    }
}

struct EmptyState: View {
    let title: String
    let detail: String
    var body: some View { VStack(spacing:9) { Text(title).font(.headline).foregroundStyle(AH.text); Text(detail).font(.subheadline).foregroundStyle(AH.muted).multilineTextAlignment(.center) }.frame(maxWidth:.infinity).padding(.vertical,24) }
}

struct Metric: View {
    let title: String
    let value: String
    var color = AH.text
    var body: some View { VStack(alignment:.leading,spacing:6) { Text(title).font(.caption).foregroundStyle(AH.muted); Text(value).font(.system(size:18,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(color).minimumScaleFactor(0.7).lineLimit(1) }.frame(maxWidth:.infinity,alignment:.leading) }
}

extension View {
    func pageBackground() -> some View { self.background(AH.background).foregroundStyle(AH.text) }
    func fieldStyle() -> some View { self.padding(14).background(AH.background,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(.white.opacity(0.1))).foregroundStyle(AH.text) }
}
