import AppKit
import SwiftUI
import SymboardCore

/// 달력 노드: 월 격자, 오늘 표시, 날짜를 누르면 일정 팝오버.
struct CalendarNodeView: View {
    @ObservedObject var box: NodeBox
    @State private var month = Date()
    /// 팝오버: (날짜, 고치는 일정 id)
    @State private var editing: (Date, UUID?)?

    static let colors = ["#F05A38", "#E9C46A", "#6FCF97", "#56A8F5", "#B48CF2", "#F28AB2"]
    var cal: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    var events: [CalendarEvent] { box.node.events ?? [] }

    var body: some View {
        let grid = Board.monthGrid(for: month, calendar: cal)
        ZStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(month, format: .dateTime.month(.wide).year()).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.symText)
                    Spacer()
                    Button { editing = (cal.startOfDay(for: Date()), nil) } label: { Label("New", systemImage: "plus") }
                        .buttonStyle(.plainHit).foregroundStyle(Color.symAccent).font(.system(size: 12, weight: .medium)).axName("New event")
                    Button("Today") { month = Date() }.buttonStyle(ChipStyle(on: false)).axName("Today")
                    Button { month = cal.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.up") }.buttonStyle(.plainHit).tip("Previous month")
                    Button { month = cal.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.down") }.buttonStyle(.plainHit).tip("Next month")
                }
                .foregroundStyle(Color.symDim)
                HStack(spacing: 0) {
                    ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { d in
                        Text(d).font(.system(size: 10)).foregroundStyle(Color.symDim).frame(maxWidth: .infinity)
                    }
                }
                GeometryReader { geo in
                    let h = geo.size.height / 6
                    VStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { r in
                            HStack(spacing: 0) {
                                ForEach(0..<7, id: \.self) { c in cell(grid[r * 7 + c], height: h) }
                            }
                        }
                    }
                }
            }
            .padding(12)
            if let (day, id) = editing {
                Color.black.opacity(0.3).onTapGesture { editing = nil }
                EventEditor(day: day, event: id.flatMap { i in events.first { $0.id == i } }) { ev in
                    box.update { n in
                        var list = n.events ?? []
                        if let i = list.firstIndex(where: { $0.id == ev.id }) { list[i] = ev } else { list.append(ev) }
                        n.events = list
                    }
                    editing = nil
                } cancel: { editing = nil } delete: {
                    if let id { box.update { $0.events?.removeAll { $0.id == id } } }
                    editing = nil
                }
            }
        }
        .background(Color.symSurface)
        .onReceive(NotificationCenter.default.publisher(for: .openEventEditor)) { note in
            guard note.object as? UUID == box.node.id, let d = note.userInfo?["day"] as? Date else { return }
            editing = (d, nil)
        }
    }

    func cell(_ day: Date, height: CGFloat) -> some View {
        let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
        let today = cal.isDateInToday(day)
        let dayEvents = events.filter { cal.isDate($0.day, inSameDayAs: day) }
        return VStack(alignment: .trailing, spacing: 2) {
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 11, weight: today ? .bold : .regular))
                .foregroundStyle(today ? Color.white : (inMonth ? Color.symText.opacity(0.8) : Color.symDim.opacity(0.5)))
                .frame(width: 20, height: 20)
                .background(Circle().fill(today ? Color.symAccent : Color.clear))
            ForEach(dayEvents.prefix(2)) { ev in
                Text(ev.title).font(.system(size: 9, weight: .medium)).lineLimit(1)
                    .foregroundStyle(Color.symText)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: ev.colorHex).opacity(0.25)))
                    .overlay(alignment: .leading) { Rectangle().fill(Color(hex: ev.colorHex)).frame(width: 2) }
                    .onTapGesture { editing = (ev.day, ev.id) }
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .top)
        .overlay(Rectangle().stroke(Color.symBorder.opacity(0.5), lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { editing = (cal.startOfDay(for: day), nil) }
    }
}

extension Notification.Name {
    static let openEventEditor = Notification.Name("symboard.openEventEditor")
}

struct EventEditor: View {
    @State private var title: String
    @State private var day: Date
    @State private var allDay: Bool
    @State private var color: String
    @State private var notes: String
    let event: CalendarEvent?
    var save: (CalendarEvent) -> Void
    var cancel: () -> Void
    var delete: () -> Void

    init(day: Date, event: CalendarEvent?, save: @escaping (CalendarEvent) -> Void, cancel: @escaping () -> Void, delete: @escaping () -> Void) {
        self.event = event
        _title = State(initialValue: event?.title ?? "")
        _day = State(initialValue: event?.day ?? day)
        _allDay = State(initialValue: event?.allDay ?? true)
        _color = State(initialValue: event?.colorHex ?? CalendarNodeView.colors[0])
        _notes = State(initialValue: event?.notes ?? "")
        self.save = save; self.cancel = cancel; self.delete = delete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("", text: $title, prompt: Text("Event title").foregroundColor(Color.symDim))
                    .textFieldStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.symText)
                Button(action: cancel) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip("Close")
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar").foregroundStyle(Color.symDim)
                DatePicker("", selection: $day, displayedComponents: .date).labelsHidden().datePickerStyle(.field)
            }
            .font(.system(size: 12))
            HStack {
                Image(systemName: "clock").foregroundStyle(Color.symDim)
                Text("All day").font(.system(size: 12)).foregroundStyle(Color.symText)
                Spacer()
                Toggle("", isOn: $allDay).toggleStyle(.switch).labelsHidden().tint(Color.symAccent).controlSize(.mini)
            }
            HStack(spacing: 8) {
                ForEach(CalendarNodeView.colors, id: \.self) { hex in
                    Button { color = hex } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white.opacity(color == hex ? 0.9 : 0), lineWidth: 2).padding(-3))
                    }
                    .buttonStyle(.plainHit).axName("Color \(hex)")
                }
            }
            TextField("", text: $notes, prompt: Text("Notes").foregroundColor(Color.symDim))
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.symText)
            HStack {
                if event != nil { Button(action: delete) { Image(systemName: "trash") }.buttonStyle(.plainHit).foregroundStyle(Color.symAccent).tip("Delete event") }
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(.plainHit).foregroundStyle(Color.symDim).axName("Cancel")
                Button(event == nil ? "Add event" : "Save") {
                    var e = event ?? CalendarEvent(title: "", day: day)
                    e.title = title.trimmingCharacters(in: .whitespaces)
                    e.day = Calendar.current.startOfDay(for: day); e.allDay = allDay; e.colorHex = color; e.notes = notes
                    save(e)
                }
                .buttonStyle(PillButtonStyle(prominent: true)).axName(event == nil ? "Add event" : "Save").disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .font(.system(size: 12))
        .padding(14)
        .frame(width: 260)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.symSurface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.symBorder))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
    }
}
