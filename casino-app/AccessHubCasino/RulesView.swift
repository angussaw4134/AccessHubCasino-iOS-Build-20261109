import SwiftUI

struct RulesView: View {
    @EnvironmentObject var store: CasinoStore
    let game: CasinoGame
    private var rule: JSONValue { store.rules[game.rawValue] }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                GameArtwork(game:game).frame(height:155).clipShape(RoundedRectangle(cornerRadius:20))
                SectionTitle(title:game.title + ", explained.",caption:"Know the rules before your first move.")
                if !store.rules.exists {
                    Panel { VStack(spacing:16) { ProgressView(); Text("Loading the current server rules…").font(.subheadline); Button("Retry") { Task { await store.loadRules() } } }.frame(maxWidth:.infinity) }
                } else {
                    Panel { VStack(alignment:.leading,spacing:16) {
                        Text("How it works").font(.headline)
                        Text(rule["text"].string).font(.subheadline).foregroundStyle(AH.muted).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                    } }
                    if rule["baseRTP"].exists {
                        Panel { VStack(alignment:.leading,spacing:16) { HStack { Metric(title:"Theoretical base RTP",value:String(format:"%.1f%%",rule["baseRTP"].double*100),color:AH.emerald); Metric(title:"Eligible stake rakeback",value:"1%") }; Text(store.rules["longRun"].string).font(.caption).foregroundStyle(AH.muted) } }
                    } else { Panel { VStack(alignment:.leading,spacing:12) { Text("Strategy matters.").font(.headline); Text("Blackjack return depends on the published rules and your playing strategy. A reproducible reference-strategy calculation is included with this app's source documentation; there is no forced target return.").font(.subheadline).foregroundStyle(AH.muted); Text("1% rakeback is calculated separately on every eligible committed stake after final settlement.").font(.caption).foregroundStyle(AH.muted) } } }
                    if game == .slots { paytable }
                    Panel { VStack(alignment:.leading,spacing:13) { Text("Credits and rounding").font(.headline); Text(store.rules["rounding"].string).font(.caption).foregroundStyle(AH.muted); Text(store.rules["rakeback"]["text"].string).font(.caption).foregroundStyle(AH.muted); Text(store.rules["disclaimer"].string).font(.caption.weight(.medium)).foregroundStyle(AH.emerald) } }
                    LearnButton(milestone:game.rawValue+".rules",title:"I've read the rules")
                    Text("Rules version: " + store.rules["version"].string).font(.caption2).foregroundStyle(AH.muted)
                }
            }.padding(20)
        }.pageBackground().navigationTitle("Rules & payouts").navigationBarTitleDisplayMode(.inline).task { await store.loadRules() }
    }
    private var paytable: some View {
        Panel {
            VStack(alignment:.leading,spacing:18) {
                Text("The paytable").font(.title3.weight(.semibold))
                Text("Multipliers below apply to one line's stake: your total stake ÷ 5. Only the longest left-to-right match on a line pays.").font(.caption).foregroundStyle(AH.muted)
                HStack { Text("Symbol").frame(maxWidth:.infinity,alignment:.leading); ForEach([3,4,5],id:\.self) { Text("\($0) in row").frame(maxWidth:.infinity) } }.font(.system(size:10,weight:.semibold)).foregroundStyle(AH.muted)
                ForEach(rule["symbols"].array.map(\.string),id:\.self) { symbol in
                    HStack {
                        VStack(spacing:3) { SlotSymbol(symbol:symbol).frame(width:32,height:36); Text(symbol.capitalized).font(.system(size:9)) }.frame(maxWidth:.infinity,alignment:.leading)
                        ForEach(0..<3,id:\.self) { index in Text(paytableValue(symbol,index:index) + "×").font(.caption.weight(.semibold)).monospacedDigit().frame(maxWidth:.infinity) }
                    }
                }
                Divider()
                Text("Five fixed paylines").font(.headline)
                ForEach(Array(rule["paylines"].array.enumerated()),id:\.offset) { index, line in HStack(spacing:14) { Text("\(index+1)").font(.caption).foregroundStyle(AH.muted).frame(width:15); PaylineDiagram(rows:line.array.map(\.int)).frame(height:43) } }
            }
        }
    }
    private func paytableValue(_ symbol: String,index: Int) -> String {
        let entry = rule["paytable"][symbol]
        return entry.array.isEmpty ? entry[String(index+3)].string : entry[index].string
    }
}

struct PaylineDiagram: View {
    let rows: [Int]
    var body: some View {
        GeometryReader { g in
            let cell = g.size.width/5
            Canvas { context,size in
                for x in 0..<5 { for y in 0..<3 {
                    let rect = CGRect(x:CGFloat(x)*cell+2,y:CGFloat(y)*size.height/3+1,width:cell-4,height:size.height/3-2)
                    context.fill(Path(roundedRect:rect,cornerRadius:2),with:.color(rows.indices.contains(x) && rows[x] == y ? AH.emerald.opacity(0.55) : AH.raised))
                } }
                var p = Path()
                for x in 0..<min(rows.count,5) { let point = CGPoint(x:(CGFloat(x)+0.5)*cell,y:(CGFloat(rows[x])+0.5)*size.height/3); if x == 0 { p.move(to:point) } else { p.addLine(to:point) } }
                context.stroke(p,with:.color(AH.emerald),lineWidth:1.5)
            }
        }.accessibilityLabel("Rows " + rows.map { String($0+1) }.joined(separator:", "))
    }
}
