import Foundation
import SQLite3

// SQLite destructor type for transient strings
private let SQLITE_TRANSIENT_TODO = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Todo Database Manager - handles all Todo-related database queries
class TodoDatabaseManager {
    static let shared = TodoDatabaseManager()
    private let dbManager = DatabaseManager.shared

    private init() {}

    // MARK: - Global Tasks

    func listGlobalTasks(status: String? = nil, limit: Int = 50) -> [GlobalTaskInfo] {
        var tasks: [GlobalTaskInfo] = []

        guard dbManager.openDatabase() else { return tasks }
        defer { dbManager.closeDatabase() }

        var query = """
            SELECT gt.*,
                   (SELECT COUNT(*) FROM todos WHERE global_task_id = gt.id) as todo_count,
                   (SELECT COUNT(*) FROM todos WHERE global_task_id = gt.id AND status = 'completed') as completed_todo_count
            FROM global_tasks gt
        """
        var params: [String] = []

        if let status = status {
            query += " WHERE gt.status = ?"
            params.append(status)
        }

        query += " ORDER BY gt.priority DESC, gt.created_at DESC LIMIT \(limit)"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(dbManager.db, query, -1, &statement, nil) == SQLITE_OK {
            for (i, param) in params.enumerated() {
                sqlite3_bind_text(statement, Int32(i + 1), param, -1, SQLITE_TRANSIENT_TODO)
            }

            while sqlite3_step(statement) == SQLITE_ROW {
                if let task = parseGlobalTask(statement: statement) {
                    tasks.append(task)
                }
            }
        }
        sqlite3_finalize(statement)

        return tasks
    }

    func getGlobalTask(id: Int) -> GlobalTaskInfo? {
        guard dbManager.openDatabase() else { return nil }
        defer { dbManager.closeDatabase() }

        let query = """
            SELECT gt.*,
                   (SELECT COUNT(*) FROM todos WHERE global_task_id = gt.id) as todo_count,
                   (SELECT COUNT(*) FROM todos WHERE global_task_id = gt.id AND status = 'completed') as completed_todo_count
            FROM global_tasks gt WHERE gt.id = ?
        """

        var statement: OpaquePointer?
        var task: GlobalTaskInfo?

        if sqlite3_prepare_v2(dbManager.db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(id))

            if sqlite3_step(statement) == SQLITE_ROW {
                task = parseGlobalTask(statement: statement)
            }
        }
        sqlite3_finalize(statement)

        return task
    }

    private func parseGlobalTask(statement: OpaquePointer?) -> GlobalTaskInfo? {
        guard let statement = statement else { return nil }

        let id = Int(sqlite3_column_int(statement, 0))

        guard let titlePtr = sqlite3_column_text(statement, 1) else { return nil }
        let title = String(cString: titlePtr)

        var description: String?
        if let descPtr = sqlite3_column_text(statement, 2) {
            description = String(cString: descPtr)
        }

        guard let statusPtr = sqlite3_column_text(statement, 3) else { return nil }
        let status = String(cString: statusPtr)
        let priority = Int(sqlite3_column_int(statement, 4))

        let createdAt = parseDate(sqlite3_column_text(statement, 5)) ?? Date()
        let updatedAt = parseDate(sqlite3_column_text(statement, 6)) ?? Date()
        let completedAt = parseDate(sqlite3_column_text(statement, 7))

        // Skip metadata_json for now (column 8)
        let todoCount = Int(sqlite3_column_int(statement, 9))
        let completedTodoCount = Int(sqlite3_column_int(statement, 10))

        return GlobalTaskInfo(
            id: id,
            title: title,
            description: description,
            status: status,
            priority: priority,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt,
            metadata: nil,
            todoCount: todoCount,
            completedTodoCount: completedTodoCount
        )
    }

    // MARK: - Todos

    func listTodos(
        projectPath: String? = nil,
        globalTaskId: Int? = nil,
        status: String? = nil,
        parentTodoId: Int? = nil,
        includeChildren: Bool = false,
        limit: Int = 50
    ) -> [ProjectTodoItem] {
        var todos: [ProjectTodoItem] = []

        guard dbManager.openDatabase() else { return todos }
        defer { dbManager.closeDatabase() }

        var query = "SELECT * FROM todos WHERE 1=1"
        var params: [Any] = []

        if let projectPath = projectPath {
            query += " AND project_path = ?"
            params.append(projectPath)
        }
        if let globalTaskId = globalTaskId {
            query += " AND global_task_id = ?"
            params.append(globalTaskId)
        }
        if let status = status {
            query += " AND status = ?"
            params.append(status)
        }
        if let parentTodoId = parentTodoId {
            query += " AND parent_todo_id = ?"
            params.append(parentTodoId)
        } else if !includeChildren {
            query += " AND parent_todo_id IS NULL"
        }

        query += " ORDER BY priority DESC, created_at DESC LIMIT \(limit)"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(dbManager.db, query, -1, &statement, nil) == SQLITE_OK {
            for (i, param) in params.enumerated() {
                if let str = param as? String {
                    sqlite3_bind_text(statement, Int32(i + 1), str, -1, SQLITE_TRANSIENT_TODO)
                } else if let int = param as? Int {
                    sqlite3_bind_int(statement, Int32(i + 1), Int32(int))
                }
            }

            while sqlite3_step(statement) == SQLITE_ROW {
                if let todo = parseTodo(statement: statement) {
                    todos.append(todo)
                }
            }
        }
        sqlite3_finalize(statement)

        // Load children in separate queries if needed
        if includeChildren {
            for i in 0..<todos.count {
                todos[i].children = loadChildren(parentId: todos[i].id)
            }
        }

        return todos
    }

    private func loadChildren(parentId: Int) -> [ProjectTodoItem] {
        // Note: database should already be open from parent call
        var children: [ProjectTodoItem] = []

        let query = "SELECT * FROM todos WHERE parent_todo_id = ? ORDER BY priority DESC, created_at"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(dbManager.db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(parentId))

            while sqlite3_step(statement) == SQLITE_ROW {
                if let todo = parseTodo(statement: statement) {
                    children.append(todo)
                }
            }
        }
        sqlite3_finalize(statement)

        return children
    }

    func getTodo(id: Int, includeChildren: Bool = false) -> ProjectTodoItem? {
        guard dbManager.openDatabase() else { return nil }
        defer { dbManager.closeDatabase() }

        let query = "SELECT * FROM todos WHERE id = ?"

        var statement: OpaquePointer?
        var todo: ProjectTodoItem?

        if sqlite3_prepare_v2(dbManager.db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(id))

            if sqlite3_step(statement) == SQLITE_ROW {
                todo = parseTodo(statement: statement)
            }
        }
        sqlite3_finalize(statement)

        if includeChildren, var t = todo {
            t.children = loadChildren(parentId: id)
            todo = t
        }

        return todo
    }

    private func parseTodo(statement: OpaquePointer?) -> ProjectTodoItem? {
        guard let statement = statement else { return nil }

        let id = Int(sqlite3_column_int(statement, 0))

        var globalTaskId: Int?
        if sqlite3_column_type(statement, 1) != SQLITE_NULL {
            globalTaskId = Int(sqlite3_column_int(statement, 1))
        }

        var parentTodoId: Int?
        if sqlite3_column_type(statement, 2) != SQLITE_NULL {
            parentTodoId = Int(sqlite3_column_int(statement, 2))
        }

        guard let projectPathPtr = sqlite3_column_text(statement, 3) else { return nil }
        let projectPath = String(cString: projectPathPtr)

        guard let titlePtr = sqlite3_column_text(statement, 4) else { return nil }
        let title = String(cString: titlePtr)

        var description: String?
        if let descPtr = sqlite3_column_text(statement, 5) {
            description = String(cString: descPtr)
        }

        guard let statusPtr = sqlite3_column_text(statement, 6) else { return nil }
        let status = String(cString: statusPtr)
        let priority = Int(sqlite3_column_int(statement, 7))

        var estimatedMinutes: Int?
        if sqlite3_column_type(statement, 8) != SQLITE_NULL {
            estimatedMinutes = Int(sqlite3_column_int(statement, 8))
        }

        var actualMinutes: Int?
        if sqlite3_column_type(statement, 9) != SQLITE_NULL {
            actualMinutes = Int(sqlite3_column_int(statement, 9))
        }

        let createdAt = parseDate(sqlite3_column_text(statement, 10)) ?? Date()
        let updatedAt = parseDate(sqlite3_column_text(statement, 11)) ?? Date()
        let completedAt = parseDate(sqlite3_column_text(statement, 12))

        var completionSummary: String?
        if let summaryPtr = sqlite3_column_text(statement, 13) {
            completionSummary = String(cString: summaryPtr)
        }

        return ProjectTodoItem(
            id: id,
            globalTaskId: globalTaskId,
            parentTodoId: parentTodoId,
            projectPath: projectPath,
            title: title,
            description: description,
            status: status,
            priority: priority,
            estimatedMinutes: estimatedMinutes,
            actualMinutes: actualMinutes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt,
            completionSummary: completionSummary,
            metadata: nil,
            children: nil,
            linkedSessions: nil
        )
    }

    // MARK: - Todo Stats

    func getProjectTodoStats(projectPath: String) -> ProjectTodoStats {
        guard dbManager.openDatabase() else {
            return ProjectTodoStats(total: 0, pending: 0, inProgress: 0, blocked: 0, completed: 0, cancelled: 0)
        }
        defer { dbManager.closeDatabase() }

        let query = """
            SELECT
                COUNT(*) as total,
                SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending,
                SUM(CASE WHEN status = 'in_progress' THEN 1 ELSE 0 END) as in_progress,
                SUM(CASE WHEN status = 'blocked' THEN 1 ELSE 0 END) as blocked,
                SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
                SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) as cancelled
            FROM todos WHERE project_path = ?
        """

        var statement: OpaquePointer?
        var stats = ProjectTodoStats(total: 0, pending: 0, inProgress: 0, blocked: 0, completed: 0, cancelled: 0)

        if sqlite3_prepare_v2(dbManager.db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, projectPath, -1, SQLITE_TRANSIENT_TODO)

            if sqlite3_step(statement) == SQLITE_ROW {
                stats = ProjectTodoStats(
                    total: Int(sqlite3_column_int(statement, 0)),
                    pending: Int(sqlite3_column_int(statement, 1)),
                    inProgress: Int(sqlite3_column_int(statement, 2)),
                    blocked: Int(sqlite3_column_int(statement, 3)),
                    completed: Int(sqlite3_column_int(statement, 4)),
                    cancelled: Int(sqlite3_column_int(statement, 5))
                )
            }
        }
        sqlite3_finalize(statement)

        return stats
    }

    func getTotalPendingTodosCount() -> Int {
        guard dbManager.openDatabase() else { return 0 }
        defer { dbManager.closeDatabase() }

        let query = "SELECT COUNT(*) FROM todos WHERE status IN ('pending', 'in_progress', 'blocked')"

        var statement: OpaquePointer?
        var count = 0

        if sqlite3_prepare_v2(dbManager.db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)

        return count
    }

    // MARK: - Workflow Runs

    func listWorkflowRuns(workflowName: String? = nil, status: String? = nil, limit: Int = 20) -> [WorkflowRunInfo] {
        var runs: [WorkflowRunInfo] = []

        guard dbManager.openDatabase() else { return runs }
        defer { dbManager.closeDatabase() }

        var query = "SELECT * FROM workflow_runs WHERE 1=1"
        var params: [String] = []

        if let workflowName = workflowName {
            query += " AND workflow_name = ?"
            params.append(workflowName)
        }
        if let status = status {
            query += " AND status = ?"
            params.append(status)
        }

        query += " ORDER BY created_at DESC LIMIT \(limit)"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(dbManager.db, query, -1, &statement, nil) == SQLITE_OK {
            for (i, param) in params.enumerated() {
                sqlite3_bind_text(statement, Int32(i + 1), param, -1, SQLITE_TRANSIENT_TODO)
            }

            while sqlite3_step(statement) == SQLITE_ROW {
                if let run = parseWorkflowRun(statement: statement) {
                    runs.append(run)
                }
            }
        }
        sqlite3_finalize(statement)

        return runs
    }

    private func parseWorkflowRun(statement: OpaquePointer?) -> WorkflowRunInfo? {
        guard let statement = statement else { return nil }

        let id = Int(sqlite3_column_int(statement, 0))

        guard let namePtr = sqlite3_column_text(statement, 1) else { return nil }
        let workflowName = String(cString: namePtr)

        var taskId: Int?
        if sqlite3_column_type(statement, 2) != SQLITE_NULL {
            taskId = Int(sqlite3_column_int(statement, 2))
        }

        guard let statusPtr = sqlite3_column_text(statement, 3) else { return nil }
        let status = String(cString: statusPtr)

        var currentStep: String?
        if let stepPtr = sqlite3_column_text(statement, 4) {
            currentStep = String(cString: stepPtr)
        }

        // Skip context_json (column 5)
        let startedAt = parseDate(sqlite3_column_text(statement, 6))
        let completedAt = parseDate(sqlite3_column_text(statement, 7))
        let createdAt = parseDate(sqlite3_column_text(statement, 8)) ?? Date()

        return WorkflowRunInfo(
            id: id,
            workflowName: workflowName,
            taskId: taskId,
            status: status,
            currentStep: currentStep,
            context: nil,
            startedAt: startedAt,
            completedAt: completedAt,
            createdAt: createdAt
        )
    }

    // MARK: - Write Operations

    /// Create a new global task
    /// - Returns: The ID of the created task, or 0 on failure
    func createGlobalTask(title: String, description: String?, priority: Int) -> Int {
        guard dbManager.openDatabase() else { return 0 }
        defer { dbManager.closeDatabase() }

        let now = ISO8601DateFormatter().string(from: Date())

        let query = """
            INSERT INTO global_tasks (title, description, status, priority, created_at, updated_at)
            VALUES (?, ?, 'active', ?, ?, ?)
            """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(dbManager.db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, title, -1, SQLITE_TRANSIENT_TODO)
            if let desc = description {
                sqlite3_bind_text(statement, 2, desc, -1, SQLITE_TRANSIENT_TODO)
            } else {
                sqlite3_bind_null(statement, 2)
            }
            sqlite3_bind_int(statement, 3, Int32(priority))
            sqlite3_bind_text(statement, 4, now, -1, SQLITE_TRANSIENT_TODO)
            sqlite3_bind_text(statement, 5, now, -1, SQLITE_TRANSIENT_TODO)

            if sqlite3_step(statement) == SQLITE_DONE {
                let taskId = Int(sqlite3_last_insert_rowid(dbManager.db))
                sqlite3_finalize(statement)
                return taskId
            }
        }
        sqlite3_finalize(statement)
        return 0
    }

    /// Create a new todo
    /// - Returns: The ID of the created todo, or 0 on failure
    func createTodo(
        globalTaskId: Int?,
        projectPath: String,
        title: String,
        description: String?,
        priority: Int,
        estimatedMinutes: Int? = nil
    ) -> Int {
        guard dbManager.openDatabase() else { return 0 }
        defer { dbManager.closeDatabase() }

        let now = ISO8601DateFormatter().string(from: Date())

        let query = """
            INSERT INTO todos (global_task_id, project_path, title, description, status, priority, estimated_minutes, created_at, updated_at)
            VALUES (?, ?, ?, ?, 'pending', ?, ?, ?, ?)
            """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(dbManager.db, query, -1, &statement, nil) == SQLITE_OK {
            if let taskId = globalTaskId {
                sqlite3_bind_int(statement, 1, Int32(taskId))
            } else {
                sqlite3_bind_null(statement, 1)
            }
            sqlite3_bind_text(statement, 2, projectPath, -1, SQLITE_TRANSIENT_TODO)
            sqlite3_bind_text(statement, 3, title, -1, SQLITE_TRANSIENT_TODO)
            if let desc = description {
                sqlite3_bind_text(statement, 4, desc, -1, SQLITE_TRANSIENT_TODO)
            } else {
                sqlite3_bind_null(statement, 4)
            }
            sqlite3_bind_int(statement, 5, Int32(priority))
            if let minutes = estimatedMinutes {
                sqlite3_bind_int(statement, 6, Int32(minutes))
            } else {
                sqlite3_bind_null(statement, 6)
            }
            sqlite3_bind_text(statement, 7, now, -1, SQLITE_TRANSIENT_TODO)
            sqlite3_bind_text(statement, 8, now, -1, SQLITE_TRANSIENT_TODO)

            if sqlite3_step(statement) == SQLITE_DONE {
                let todoId = Int(sqlite3_last_insert_rowid(dbManager.db))
                sqlite3_finalize(statement)
                return todoId
            }
        }
        sqlite3_finalize(statement)
        return 0
    }

    // MARK: - Update Operations

    /// Update a todo
    /// - Returns: true if successful
    func updateTodo(
        id: Int,
        title: String? = nil,
        description: String? = nil,
        status: String? = nil,
        priority: Int? = nil,
        estimatedMinutes: Int? = nil
    ) -> Bool {
        guard dbManager.openDatabase() else { return false }
        defer { dbManager.closeDatabase() }

        var setClauses: [String] = []
        var params: [Any] = []

        if let title = title {
            setClauses.append("title = ?")
            params.append(title)
        }
        if let description = description {
            setClauses.append("description = ?")
            params.append(description)
        }
        if let status = status {
            setClauses.append("status = ?")
            params.append(status)
            if status == "completed" {
                setClauses.append("completed_at = ?")
                params.append(ISO8601DateFormatter().string(from: Date()))
            }
        }
        if let priority = priority {
            setClauses.append("priority = ?")
            params.append(priority)
        }
        if let estimatedMinutes = estimatedMinutes {
            setClauses.append("estimated_minutes = ?")
            params.append(estimatedMinutes)
        }

        guard !setClauses.isEmpty else { return false }

        setClauses.append("updated_at = ?")
        params.append(ISO8601DateFormatter().string(from: Date()))
        params.append(id)

        let query = "UPDATE todos SET \(setClauses.joined(separator: ", ")) WHERE id = ?"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(dbManager.db, query, -1, &statement, nil) == SQLITE_OK {
            for (i, param) in params.enumerated() {
                if let str = param as? String {
                    sqlite3_bind_text(statement, Int32(i + 1), str, -1, SQLITE_TRANSIENT_TODO)
                } else if let int = param as? Int {
                    sqlite3_bind_int(statement, Int32(i + 1), Int32(int))
                }
            }

            let result = sqlite3_step(statement) == SQLITE_DONE
            sqlite3_finalize(statement)
            return result
        }
        sqlite3_finalize(statement)
        return false
    }

    /// Delete a todo (children become independent)
    /// - Returns: true if successful
    func deleteTodo(id: Int) -> Bool {
        guard dbManager.openDatabase() else { return false }
        defer { dbManager.closeDatabase() }

        // First, set children's parent_todo_id to NULL
        var statement: OpaquePointer?
        let orphanQuery = "UPDATE todos SET parent_todo_id = NULL, updated_at = ? WHERE parent_todo_id = ?"
        if sqlite3_prepare_v2(dbManager.db, orphanQuery, -1, &statement, nil) == SQLITE_OK {
            let now = ISO8601DateFormatter().string(from: Date())
            sqlite3_bind_text(statement, 1, now, -1, SQLITE_TRANSIENT_TODO)
            sqlite3_bind_int(statement, 2, Int32(id))
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)

        // Then delete the todo
        let deleteQuery = "DELETE FROM todos WHERE id = ?"
        if sqlite3_prepare_v2(dbManager.db, deleteQuery, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(id))
            let result = sqlite3_step(statement) == SQLITE_DONE
            sqlite3_finalize(statement)
            return result
        }
        sqlite3_finalize(statement)
        return false
    }

    /// Update a global task
    /// - Returns: true if successful
    func updateGlobalTask(
        id: Int,
        title: String? = nil,
        description: String? = nil,
        status: String? = nil,
        priority: Int? = nil
    ) -> Bool {
        guard dbManager.openDatabase() else { return false }
        defer { dbManager.closeDatabase() }

        var setClauses: [String] = []
        var params: [Any] = []

        if let title = title {
            setClauses.append("title = ?")
            params.append(title)
        }
        if let description = description {
            setClauses.append("description = ?")
            params.append(description)
        }
        if let status = status {
            setClauses.append("status = ?")
            params.append(status)
            if status == "completed" {
                setClauses.append("completed_at = ?")
                params.append(ISO8601DateFormatter().string(from: Date()))
            }
        }
        if let priority = priority {
            setClauses.append("priority = ?")
            params.append(priority)
        }

        guard !setClauses.isEmpty else { return false }

        setClauses.append("updated_at = ?")
        params.append(ISO8601DateFormatter().string(from: Date()))
        params.append(id)

        let query = "UPDATE global_tasks SET \(setClauses.joined(separator: ", ")) WHERE id = ?"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(dbManager.db, query, -1, &statement, nil) == SQLITE_OK {
            for (i, param) in params.enumerated() {
                if let str = param as? String {
                    sqlite3_bind_text(statement, Int32(i + 1), str, -1, SQLITE_TRANSIENT_TODO)
                } else if let int = param as? Int {
                    sqlite3_bind_int(statement, Int32(i + 1), Int32(int))
                }
            }

            let result = sqlite3_step(statement) == SQLITE_DONE
            sqlite3_finalize(statement)
            return result
        }
        sqlite3_finalize(statement)
        return false
    }

    /// Delete a global task
    /// - Returns: true if successful
    func deleteGlobalTask(id: Int) -> Bool {
        guard dbManager.openDatabase() else { return false }
        defer { dbManager.closeDatabase() }

        // Set todos' global_task_id to NULL first
        var statement: OpaquePointer?
        let orphanQuery = "UPDATE todos SET global_task_id = NULL, updated_at = ? WHERE global_task_id = ?"
        if sqlite3_prepare_v2(dbManager.db, orphanQuery, -1, &statement, nil) == SQLITE_OK {
            let now = ISO8601DateFormatter().string(from: Date())
            sqlite3_bind_text(statement, 1, now, -1, SQLITE_TRANSIENT_TODO)
            sqlite3_bind_int(statement, 2, Int32(id))
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)

        // Then delete the global task
        let deleteQuery = "DELETE FROM global_tasks WHERE id = ?"
        if sqlite3_prepare_v2(dbManager.db, deleteQuery, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(id))
            let result = sqlite3_step(statement) == SQLITE_DONE
            sqlite3_finalize(statement)
            return result
        }
        sqlite3_finalize(statement)
        return false
    }

    // MARK: - Helpers

    private func parseDate(_ ptr: UnsafePointer<UInt8>?) -> Date? {
        guard let ptr = ptr else { return nil }
        let dateStr = String(cString: ptr)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter.date(from: dateStr) {
            return date
        }

        // Try ISO format
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: dateStr)
    }
}
