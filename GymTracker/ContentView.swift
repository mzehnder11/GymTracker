import SwiftUI
import Charts
import Combine

// MARK: - DATE FORMATTER

extension Date {
    func formattedString() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}

// MARK: - MODELS

struct Exercise: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var logs: [WorkoutLog]
    
    var estimatedOneRepMax: Double? {
        guard let lastLog = logs.last else { return nil }
        if lastLog.reps == 1 {
            return lastLog.weight
        }
        return lastLog.weight * (1 + Double(lastLog.reps) / 30.0)
    }
    
    // Progressive Overload Metriken
    var progressiveOverloadScore: Double? {
        guard logs.count >= 2 else { return nil }
        let sortedLogs = logs.sorted { $0.date < $1.date }
        let first = sortedLogs.first!
        let last = sortedLogs.last!
        
        let firstScore = first.weight * Double(first.reps)
        let lastScore = last.weight * Double(last.reps)
        
        return ((lastScore - firstScore) / firstScore) * 100
    }
    
    var averageIntensity: Double? {
        guard !logs.isEmpty else { return nil }
        let totalIntensity = logs.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
        return totalIntensity / Double(logs.count)
    }
}

struct WorkoutLog: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let weight: Double
    let reps: Int
    let sessionId: UUID?
    
    var volume: Double {
        weight * Double(reps)
    }
    
    // Intensitätsscore für Progressive Overload
    var intensityScore: Double {
        weight * Double(reps)
    }
}

struct TrainingSession: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var date: Date
    var exerciseIds: [UUID]
    var notes: String
    
    func totalVolume(from store: GymStore) -> Double {
        var total = 0.0
        for exercise in store.exercises where exerciseIds.contains(exercise.id) {
            for log in exercise.logs where log.sessionId == id {
                total += log.volume
            }
        }
        return total
    }
}

struct TrainingPlan: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var exerciseIds: [UUID]
    var notes: String
}

// MARK: - STORE (Persistence)

final class GymStore: ObservableObject {
    
    @Published var exercises: [Exercise] = []
    @Published var sessions: [TrainingSession] = []
    @Published var plans: [TrainingPlan] = []
    
    private let exercisesKey = "gym_data"
    private let sessionsKey = "gym_sessions"
    private let plansKey = "gym_plans"
    
    init() {
        load()
    }
    
    func addExercise(name: String) {
        let exercise = Exercise(id: UUID(), name: name, logs: [])
        exercises.append(exercise)
        save()
    }
    
    func updateExercise(_ exercise: Exercise, name: String) {
        guard let index = exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        exercises[index].name = name
        save()
    }
    
    func deleteExercise(_ exercise: Exercise) {
        exercises.removeAll { $0.id == exercise.id }
        save()
    }
    
    func addLog(to exercise: Exercise, weight: Double, reps: Int, sessionId: UUID? = nil) {
        guard let index = exercises.firstIndex(of: exercise) else { return }
        let log = WorkoutLog(
            id: UUID(),
            date: Date(),
            weight: weight,
            reps: reps,
            sessionId: sessionId
        )
        exercises[index].logs.append(log)
        save()
    }
    
    func updateLog(exerciseId: UUID, log: WorkoutLog, weight: Double, reps: Int) {
        guard let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseId }),
              let logIndex = exercises[exerciseIndex].logs.firstIndex(where: { $0.id == log.id }) else { return }
        
        let updatedLog = WorkoutLog(
            id: log.id,
            date: log.date,
            weight: weight,
            reps: reps,
            sessionId: log.sessionId
        )
        exercises[exerciseIndex].logs[logIndex] = updatedLog
        save()
    }
    
    func deleteLog(exerciseId: UUID, logId: UUID) {
        guard let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        exercises[exerciseIndex].logs.removeAll { $0.id == logId }
        save()
    }
    
    func addSession(name: String, exerciseIds: [UUID], notes: String = "") {
        let session = TrainingSession(
            id: UUID(),
            name: name,
            date: Date(),
            exerciseIds: exerciseIds,
            notes: notes
        )
        sessions.append(session)
        save()
    }
    
    func updateSession(_ session: TrainingSession, name: String, notes: String) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].name = name
        sessions[index].notes = notes
        save()
    }
    
    func deleteSession(_ session: TrainingSession) {
        for exerciseIndex in exercises.indices {
            exercises[exerciseIndex].logs.removeAll { $0.sessionId == session.id }
        }
        sessions.removeAll { $0.id == session.id }
        save()
    }
    
    func addPlan(name: String, exerciseIds: [UUID], notes: String = "") {
        let plan = TrainingPlan(
            id: UUID(),
            name: name,
            exerciseIds: exerciseIds,
            notes: notes
        )
        plans.append(plan)
        save()
    }
    
    func updatePlan(_ plan: TrainingPlan, name: String, exerciseIds: [UUID], notes: String) {
        guard let index = plans.firstIndex(where: { $0.id == plan.id }) else { return }
        plans[index].name = name
        plans[index].exerciseIds = exerciseIds
        plans[index].notes = notes
        save()
    }
    
    func deletePlan(_ plan: TrainingPlan) {
        plans.removeAll { $0.id == plan.id }
        save()
    }
    
    // MARK: - Persistence
    
    private func save() {
        if let data = try? JSONEncoder().encode(exercises) {
            UserDefaults.standard.set(data, forKey: exercisesKey)
        }
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
        if let data = try? JSONEncoder().encode(plans) {
            UserDefaults.standard.set(data, forKey: plansKey)
        }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: exercisesKey),
           let decoded = try? JSONDecoder().decode([Exercise].self, from: data) {
            exercises = decoded
        }
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let decoded = try? JSONDecoder().decode([TrainingSession].self, from: data) {
            sessions = decoded
        }
        if let data = UserDefaults.standard.data(forKey: plansKey),
           let decoded = try? JSONDecoder().decode([TrainingPlan].self, from: data) {
            plans = decoded
        }
    }
}

// MARK: - CONTENT VIEW

struct ContentView: View {
    
    @StateObject private var store = GymStore()
    
    var body: some View {
        TabView {
            ExercisesListView()
                .environmentObject(store)
                .tabItem {
                    Label("Übungen", systemImage: "dumbbell")
                }
            
            SessionsListView()
                .environmentObject(store)
                .tabItem {
                    Label("Sessions", systemImage: "calendar")
                }
            
            PlansListView()
                .environmentObject(store)
                .tabItem {
                    Label("Pläne", systemImage: "list.bullet.clipboard")
                }
        }
    }
}

// MARK: - EXERCISES LIST

struct ExercisesListView: View {
    
    @EnvironmentObject var store: GymStore
    @State private var showAddExercise = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.exercises) { exercise in
                    NavigationLink {
                        ExerciseDetailView(exercise: exercise)
                            .environmentObject(store)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name)
                                .font(.headline)
                            
                            HStack(spacing: 12) {
                                if let oneRM = exercise.estimatedOneRepMax {
                                    Text("1RM: \(String(format: "%.1f", oneRM)) kg")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let progress = exercise.progressiveOverloadScore {
                                    HStack(spacing: 2) {
                                        Image(systemName: progress >= 0 ? "arrow.up.right" : "arrow.down.right")
                                            .font(.caption2)
                                        Text("\(String(format: "%.1f", abs(progress)))%")
                                            .font(.caption)
                                    }
                                    .foregroundColor(progress >= 0 ? .green : .red)
                                }
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        store.deleteExercise(store.exercises[index])
                    }
                }
            }
            .navigationTitle("Übungen")
            .toolbar {
                Button {
                    showAddExercise = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showAddExercise) {
                AddExerciseView()
                    .environmentObject(store)
            }
        }
    }
}

// MARK: - ADD/EDIT EXERCISE

struct AddExerciseView: View {
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GymStore
    
    let exerciseToEdit: Exercise?
    @State private var name = ""
    
    init(exerciseToEdit: Exercise? = nil) {
        self.exerciseToEdit = exerciseToEdit
        _name = State(initialValue: exerciseToEdit?.name ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Übungsname", text: $name)
            }
            .navigationTitle(exerciseToEdit == nil ? "Neue Übung" : "Übung bearbeiten")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(exerciseToEdit == nil ? "Hinzufügen" : "Speichern") {
                        if let exercise = exerciseToEdit {
                            store.updateExercise(exercise, name: name)
                        } else {
                            store.addExercise(name: name)
                        }
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - EXERCISE DETAIL

struct ExerciseDetailView: View {
    
    let exercise: Exercise
    @EnvironmentObject var store: GymStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var showAddLog = false
    @State private var showEditExercise = false
    @State private var logToEdit: WorkoutLog?
    
    var currentExercise: Exercise? {
        store.exercises.first { $0.id == exercise.id }
    }
    
    var totalVolume: Double {
        currentExercise?.logs.reduce(0) { $0 + $1.volume } ?? 0
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // Progressive Overload Highlight
                if let ex = currentExercise, ex.logs.count >= 2 {
                    ProgressiveOverloadCard(exercise: ex)
                }
                
                // Statistiken
                VStack(alignment: .leading, spacing: 8) {
                    Text("Statistiken")
                        .font(.headline)
                    
                    HStack {
                        StatCard(title: "Gesamt-Volumen", value: "\(String(format: "%.0f", totalVolume)) kg")
                        StatCard(title: "Trainings", value: "\(currentExercise?.logs.count ?? 0)")
                    }
                    
                    HStack {
                        if let oneRM = currentExercise?.estimatedOneRepMax {
                            StatCard(title: "Geschätztes 1RM", value: "\(String(format: "%.1f", oneRM)) kg")
                        }
                        
                        if let avgIntensity = currentExercise?.averageIntensity {
                            StatCard(title: "Ø Intensität", value: "\(String(format: "%.0f", avgIntensity)) kg")
                        }
                    }
                }
                
                // Progressive Overload Chart
                if let ex = currentExercise, ex.logs.count >= 2 {
                    Text("Progressive Overload")
                        .font(.headline)
                    progressiveOverloadChart(for: ex)
                }
                
                // Weitere Charts
                if let ex = currentExercise, !ex.logs.isEmpty {
                    Text("Gewicht & Wiederholungen")
                        .font(.headline)
                        .padding(.top)
                    combinedWeightRepsChart(for: ex)
                    
                    Text("Volumenverlauf")
                        .font(.headline)
                        .padding(.top)
                    volumeChart(for: ex)
                }
                
                Divider()
                
                // Logs mit Vergleich
                Text("Verlauf")
                    .font(.headline)
                
                if let ex = currentExercise {
                    let sortedLogs = ex.logs.sorted(by: { $0.date > $1.date })
                    ForEach(Array(sortedLogs.enumerated()), id: \.element.id) { index, log in
                        let previousLog = index < sortedLogs.count - 1 ? sortedLogs[index + 1] : nil
                        LogRowView(log: log, previousLog: previousLog, onTap: {
                            logToEdit = log
                        }, onDelete: {
                            store.deleteLog(exerciseId: exercise.id, logId: log.id)
                        })
                    }
                }
            }
            .padding()
        }
        .navigationTitle(currentExercise?.name ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddLog = true
                } label: {
                    Image(systemName: "plus.circle")
                }
            }
            
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button {
                        showEditExercise = true
                    } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        store.deleteExercise(exercise)
                        dismiss()
                    } label: {
                        Label("Übung löschen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showAddLog) {
            if let ex = currentExercise {
                AddLogView(exercise: ex)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showEditExercise) {
            if let ex = currentExercise {
                AddExerciseView(exerciseToEdit: ex)
                    .environmentObject(store)
            }
        }
        .sheet(item: $logToEdit) { log in
            if let ex = currentExercise {
                EditLogView(exercise: ex, log: log)
                    .environmentObject(store)
            }
        }
    }
    
    // MARK: - Charts
    
    private func progressiveOverloadChart(for exercise: Exercise) -> some View {
        Chart {
            ForEach(exercise.logs) { log in
                LineMark(
                    x: .value("Datum", log.date),
                    y: .value("Intensität", log.intensityScore)
                )
                .foregroundStyle(.purple)
                .symbol(Circle())
                .interpolationMethod(.catmullRom)
                
                PointMark(
                    x: .value("Datum", log.date),
                    y: .value("Intensität", log.intensityScore)
                )
                .foregroundStyle(.purple)
            }
        }
        .chartYAxisLabel("Intensität (kg × reps)")
        .frame(height: 220)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func combinedWeightRepsChart(for exercise: Exercise) -> some View {
        Chart {
            ForEach(exercise.logs) { log in
                LineMark(
                    x: .value("Datum", log.date),
                    y: .value("Gewicht", log.weight)
                )
                .foregroundStyle(.blue)
                .symbol(Circle())
                
                BarMark(
                    x: .value("Datum", log.date),
                    y: .value("Wiederholungen", Double(log.reps))
                )
                .foregroundStyle(.orange.opacity(0.5))
            }
        }
        .frame(height: 200)
    }
    
    private func volumeChart(for exercise: Exercise) -> some View {
        Chart {
            ForEach(exercise.logs) { log in
                BarMark(
                    x: .value("Datum", log.date),
                    y: .value("Volumen", log.volume)
                )
                .foregroundStyle(.green)
            }
        }
        .frame(height: 200)
    }
}

// MARK: - PROGRESSIVE OVERLOAD CARD

struct ProgressiveOverloadCard: View {
    let exercise: Exercise
    
    var progressInfo: (change: Double, isPositive: Bool, text: String) {
        guard let score = exercise.progressiveOverloadScore else {
            return (0, false, "Keine Daten")
        }
        
        let isPositive = score >= 0
        let text: String
        
        if abs(score) < 5 {
            text = "Plateau"
        } else if abs(score) < 15 {
            text = isPositive ? "Leichte Steigerung" : "Leichter Rückgang"
        } else if abs(score) < 30 {
            text = isPositive ? "Gute Steigerung" : "Deutlicher Rückgang"
        } else {
            text = isPositive ? "Starke Steigerung! 💪" : "Starker Rückgang"
        }
        
        return (score, isPositive, text)
    }
    
    var body: some View {
        let info = progressInfo
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: info.isPositive ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                    .foregroundColor(info.isPositive ? .green : .red)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Progressive Overload")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(info.text)
                        .font(.headline)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(String(format: "%.1f", abs(info.change)))%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(info.isPositive ? .green : .red)
                    Text("seit Start")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [
                        info.isPositive ? Color.green.opacity(0.1) : Color.red.opacity(0.1),
                        info.isPositive ? Color.green.opacity(0.05) : Color.red.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
        }
    }
}

// MARK: - LOG ROW VIEW

struct LogRowView: View {
    let log: WorkoutLog
    let previousLog: WorkoutLog?
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var changes: (weight: Double, reps: Int, volume: Double)? {
        guard let prev = previousLog else { return nil }
        return (
            log.weight - prev.weight,
            log.reps - prev.reps,
            log.volume - prev.volume
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(log.date.formattedString())
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(String(format: "%.1f", log.weight)) kg × \(log.reps)")
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Text("Volumen: \(String(format: "%.0f", log.volume)) kg")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                if let changes = changes {
                    VStack(alignment: .trailing, spacing: 4) {
                        if changes.weight != 0 {
                            HStack(spacing: 2) {
                                Image(systemName: changes.weight > 0 ? "arrow.up" : "arrow.down")
                                    .font(.caption2)
                                Text("\(String(format: "%.1f", abs(changes.weight))) kg")
                                    .font(.caption)
                            }
                            .foregroundColor(changes.weight > 0 ? .green : .red)
                        }
                        
                        if changes.reps != 0 {
                            HStack(spacing: 2) {
                                Image(systemName: changes.reps > 0 ? "arrow.up" : "arrow.down")
                                    .font(.caption2)
                                Text("\(abs(changes.reps)) reps")
                                    .font(.caption)
                            }
                            .foregroundColor(changes.reps > 0 ? .green : .red)
                        }
                        
                        if changes.volume != 0 {
                            HStack(spacing: 2) {
                                Image(systemName: changes.volume > 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption2)
                                Text("\(String(format: "%.0f", abs(changes.volume))) kg")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(changes.volume > 0 ? .green : .red)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }
}

// MARK: - STAT CARD

struct StatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - ADD LOG

struct AddLogView: View {
    
    let exercise: Exercise
    @EnvironmentObject var store: GymStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var weight = ""
    @State private var reps = ""
    
    var lastLog: WorkoutLog? {
        exercise.logs.sorted { $0.date > $1.date }.first
    }
    
    var body: some View {
        NavigationStack {
            Form {
                if let last = lastLog {
                    Section("Letztes Training") {
                        HStack {
                            Text("\(String(format: "%.1f", last.weight)) kg × \(last.reps)")
                            Spacer()
                            Text("Volumen: \(String(format: "%.0f", last.volume)) kg")
                                .foregroundColor(.secondary)
                        }
                        .font(.callout)
                    }
                }
                
                Section("Neues Training") {
                    TextField("Gewicht (kg)", text: $weight)
                        .keyboardType(.decimalPad)
                    
                    TextField("Wiederholungen", text: $reps)
                        .keyboardType(.numberPad)
                }
                
                if let w = Double(weight), let r = Int(reps) {
                    Section("Vorschau") {
                        HStack {
                            Text("Volumen:")
                            Spacer()
                            Text("\(String(format: "%.0f", w * Double(r))) kg")
                                .fontWeight(.semibold)
                        }
                        
                        if let last = lastLog {
                            let volumeChange = (w * Double(r)) - last.volume
                            HStack {
                                Text("Veränderung:")
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: volumeChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                                        .font(.caption)
                                    Text("\(String(format: "%.0f", abs(volumeChange))) kg")
                                }
                                .foregroundColor(volumeChange >= 0 ? .green : .red)
                                .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Training eintragen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        if let w = Double(weight),
                           let r = Int(reps) {
                            store.addLog(to: exercise, weight: w, reps: r)
                            dismiss()
                        }
                    }
                    .disabled(weight.isEmpty || reps.isEmpty)
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - EDIT LOG

struct EditLogView: View {
    
    let exercise: Exercise
    let log: WorkoutLog
    @EnvironmentObject var store: GymStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var weight = ""
    @State private var reps = ""
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Gewicht (kg)", text: $weight)
                    .keyboardType(.decimalPad)
                
                TextField("Wiederholungen", text: $reps)
                    .keyboardType(.numberPad)
                
                if let w = Double(weight), let r = Int(reps) {
                    Section {
                        HStack {
                            Text("Volumen:")
                            Spacer()
                            Text("\(String(format: "%.0f", w * Double(r))) kg")
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle("Log bearbeiten")
            .onAppear {
                weight = String(log.weight)
                reps = String(log.reps)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        if let w = Double(weight),
                           let r = Int(reps) {
                            store.updateLog(exerciseId: exercise.id, log: log, weight: w, reps: r)
                            dismiss()
                        }
                    }
                    .disabled(weight.isEmpty || reps.isEmpty)
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - SESSIONS LIST

struct SessionsListView: View {
    
    @EnvironmentObject var store: GymStore
    @State private var showAddSession = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.sessions.sorted(by: { $0.date > $1.date })) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                            .environmentObject(store)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.name)
                                .font(.headline)
                            Text(session.date.formattedString())
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Volumen: \(String(format: "%.0f", session.totalVolume(from: store))) kg")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .onDelete { indexSet in
                    let sortedSessions = store.sessions.sorted(by: { $0.date > $1.date })
                    for index in indexSet {
                        store.deleteSession(sortedSessions[index])
                    }
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                Button {
                    showAddSession = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showAddSession) {
                AddSessionView()
                    .environmentObject(store)
            }
        }
    }
}

// MARK: - ADD SESSION

struct AddSessionView: View {
    
    @EnvironmentObject var store: GymStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var notes = ""
    @State private var selectedExerciseIds: Set<UUID> = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Session-Name") {
                    TextField("z.B. Push Day", text: $name)
                }
                
                Section("Übungen auswählen") {
                    ForEach(store.exercises) { exercise in
                        Button {
                            if selectedExerciseIds.contains(exercise.id) {
                                selectedExerciseIds.remove(exercise.id)
                            } else {
                                selectedExerciseIds.insert(exercise.id)
                            }
                        } label: {
                            HStack {
                                Text(exercise.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedExerciseIds.contains(exercise.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                Section("Notizen") {
                    TextEditor(text: $notes)
                        .frame(height: 80)
                }
            }
            .navigationTitle("Neue Session")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") {
                        store.addSession(
                            name: name,
                            exerciseIds: Array(selectedExerciseIds),
                            notes: notes
                        )
                        dismiss()
                    }
                    .disabled(name.isEmpty || selectedExerciseIds.isEmpty)
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - SESSION DETAIL

struct SessionDetailView: View {
    
    let session: TrainingSession
    @EnvironmentObject var store: GymStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var showAddLog = false
    @State private var selectedExercise: Exercise?
    @State private var showEditSession = false
    
    var currentSession: TrainingSession? {
        store.sessions.first { $0.id == session.id }
    }
    
    var sessionExercises: [Exercise] {
        guard let sess = currentSession else { return [] }
        return store.exercises.filter { sess.exerciseIds.contains($0.id) }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Session Info")
                        .font(.headline)
                    
                    if let sess = currentSession {
                        Text(sess.date.formattedString())
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if !sess.notes.isEmpty {
                            Text(sess.notes)
                                .font(.body)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        
                        StatCard(
                            title: "Gesamt-Volumen",
                            value: "\(String(format: "%.0f", sess.totalVolume(from: store))) kg"
                        )
                    }
                }
                
                Divider()
                
                Text("Übungen")
                    .font(.headline)
                
                ForEach(sessionExercises) { exercise in
                    Button {
                        selectedExercise = exercise
                        showAddLog = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(exercise.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                let sessionLogs = exercise.logs.filter { $0.sessionId == session.id }
                                if !sessionLogs.isEmpty {
                                    Text("\(sessionLogs.count) Sätze")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Noch keine Sätze")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    let logs = exercise.logs.filter { $0.sessionId == session.id }
                    ForEach(logs) { log in
                        HStack {
                            Text("\(String(format: "%.1f", log.weight)) kg × \(log.reps)")
                            Spacer()
                            Text("\(String(format: "%.0f", log.volume)) kg")
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal)
                        .font(.caption)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(currentSession?.name ?? "")
        .toolbar {
            Menu {
                Button {
                    showEditSession = true
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                }
                
                Button(role: .destructive) {
                    store.deleteSession(session)
                    dismiss()
                } label: {
                    Label("Session löschen", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .sheet(isPresented: $showAddLog) {
            if let exercise = selectedExercise {
                AddLogToSessionView(exercise: exercise, sessionId: session.id)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showEditSession) {
            if let sess = currentSession {
                EditSessionView(session: sess)
                    .environmentObject(store)
            }
        }
    }
}

// MARK: - EDIT SESSION

struct EditSessionView: View {
    
    let session: TrainingSession
    @EnvironmentObject var store: GymStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Session-Name") {
                    TextField("Name", text: $name)
                }
                
                Section("Notizen") {
                    TextEditor(text: $notes)
                        .frame(height: 80)
                }
            }
            .navigationTitle("Session bearbeiten")
            .onAppear {
                name = session.name
                notes = session.notes
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        store.updateSession(session, name: name, notes: notes)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - ADD LOG TO SESSION

struct AddLogToSessionView: View {
    
    let exercise: Exercise
    let sessionId: UUID
    @EnvironmentObject var store: GymStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var weight = ""
    @State private var reps = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Übung") {
                    Text(exercise.name)
                        .font(.headline)
                }
                
                TextField("Gewicht (kg)", text: $weight)
                    .keyboardType(.decimalPad)
                
                TextField("Wiederholungen", text: $reps)
                    .keyboardType(.numberPad)
                
                if let w = Double(weight), let r = Int(reps) {
                    Section {
                        HStack {
                            Text("Volumen:")
                            Spacer()
                            Text("\(String(format: "%.0f", w * Double(r))) kg")
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle("Satz hinzufügen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        if let w = Double(weight),
                           let r = Int(reps) {
                            store.addLog(to: exercise, weight: w, reps: r, sessionId: sessionId)
                            dismiss()
                        }
                    }
                    .disabled(weight.isEmpty || reps.isEmpty)
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - PLANS LIST

struct PlansListView: View {
    
    @EnvironmentObject var store: GymStore
    @State private var showAddPlan = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.plans) { plan in
                    NavigationLink {
                        PlanDetailView(plan: plan)
                            .environmentObject(store)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.name)
                                .font(.headline)
                            Text("\(plan.exerciseIds.count) Übungen")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        store.deletePlan(store.plans[index])
                    }
                }
            }
            .navigationTitle("Trainingspläne")
            .toolbar {
                Button {
                    showAddPlan = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showAddPlan) {
                AddPlanView()
                    .environmentObject(store)
            }
        }
    }
}

// MARK: - ADD/EDIT PLAN

struct AddPlanView: View {
    
    @EnvironmentObject var store: GymStore
    @Environment(\.dismiss) private var dismiss
    
    let planToEdit: TrainingPlan?
    @State private var name = ""
    @State private var notes = ""
    @State private var selectedExerciseIds: Set<UUID> = []
    
    init(planToEdit: TrainingPlan? = nil) {
        self.planToEdit = planToEdit
        _name = State(initialValue: planToEdit?.name ?? "")
        _notes = State(initialValue: planToEdit?.notes ?? "")
        _selectedExerciseIds = State(initialValue: Set(planToEdit?.exerciseIds ?? []))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Plan-Name") {
                    TextField("z.B. Push/Pull/Legs", text: $name)
                }
                
                Section("Übungen auswählen") {
                    ForEach(store.exercises) { exercise in
                        Button {
                            if selectedExerciseIds.contains(exercise.id) {
                                selectedExerciseIds.remove(exercise.id)
                            } else {
                                selectedExerciseIds.insert(exercise.id)
                            }
                        } label: {
                            HStack {
                                Text(exercise.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedExerciseIds.contains(exercise.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                Section("Notizen") {
                    TextEditor(text: $notes)
                        .frame(height: 80)
                }
            }
            .navigationTitle(planToEdit == nil ? "Neuer Plan" : "Plan bearbeiten")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(planToEdit == nil ? "Erstellen" : "Speichern") {
                        if let plan = planToEdit {
                            store.updatePlan(plan, name: name, exerciseIds: Array(selectedExerciseIds), notes: notes)
                        } else {
                            store.addPlan(name: name, exerciseIds: Array(selectedExerciseIds), notes: notes)
                        }
                        dismiss()
                    }
                    .disabled(name.isEmpty || selectedExerciseIds.isEmpty)
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - PLAN DETAIL

struct PlanDetailView: View {
    
    let plan: TrainingPlan
    @EnvironmentObject var store: GymStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var showStartSession = false
    @State private var showEditPlan = false
    
    var currentPlan: TrainingPlan? {
        store.plans.first { $0.id == plan.id }
    }
    
    var planExercises: [Exercise] {
        guard let p = currentPlan else { return [] }
        return store.exercises.filter { p.exerciseIds.contains($0.id) }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                if let p = currentPlan, !p.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Beschreibung")
                            .font(.headline)
                        Text(p.notes)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Übungen (\(planExercises.count))")
                        .font(.headline)
                    
                    ForEach(planExercises) { exercise in
                        HStack {
                            Text(exercise.name)
                            Spacer()
                            if let oneRM = exercise.estimatedOneRepMax {
                                Text("1RM: \(String(format: "%.1f", oneRM)) kg")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                Button {
                    showStartSession = true
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Session starten")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding(.top)
            }
            .padding()
        }
        .navigationTitle(currentPlan?.name ?? "")
        .toolbar {
            Menu {
                Button {
                    showEditPlan = true
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                }
                
                Button(role: .destructive) {
                    store.deletePlan(plan)
                    dismiss()
                } label: {
                    Label("Plan löschen", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .sheet(isPresented: $showStartSession) {
            if let p = currentPlan {
                StartSessionFromPlanView(plan: p)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showEditPlan) {
            if let p = currentPlan {
                AddPlanView(planToEdit: p)
                    .environmentObject(store)
            }
        }
    }
}

// MARK: - START SESSION FROM PLAN

struct StartSessionFromPlanView: View {
    
    let plan: TrainingPlan
    @EnvironmentObject var store: GymStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var sessionName = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Session-Name") {
                    TextField("z.B. \(plan.name) - Tag 1", text: $sessionName)
                }
                
                Section("Übungen") {
                    ForEach(store.exercises.filter { plan.exerciseIds.contains($0.id) }) { exercise in
                        Text(exercise.name)
                    }
                }
            }
            .navigationTitle("Session starten")
            .onAppear {
                sessionName = plan.name
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Starten") {
                        store.addSession(
                            name: sessionName,
                            exerciseIds: plan.exerciseIds,
                            notes: "Basierend auf Plan: \(plan.name)"
                        )
                        dismiss()
                    }
                    .disabled(sessionName.isEmpty)
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
