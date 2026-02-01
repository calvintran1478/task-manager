package main

import "core:fmt"
import "core:mem"
import "core:encoding/csv"
import "core:strings"
import "core:strconv"
import "core:slice"
import "core:bufio"
import "core:os"

Task :: struct {
    name: string,
    status: string,
    due_date: string
}

DATA_FILE :: ""

/*
 * Decode status from file input
 */
decode_status :: proc "contextless" (number: string) -> string {
    switch number {
    case "0":
        return "Not Started"
    case "1":
        return "In Progress"
    case "2":
        return "Complete"
    case:
        return ""
    }
}

/*
 * Encode status for file writing
 */
encode_status :: proc "contextless" (status: string) -> string {
    switch status {
    case "Not Started":
        return "0"
    case "In Progress":
        return "1"
    case "Complete":
        return "2"
    case:
        return ""
    }
}

/*
 * Load tasks from CSV file
 */
read_tasks :: proc(filename: string) -> (map[string][dynamic]Task, []byte) {
    // Open file
    file, err := os.open(filename, os.O_RDONLY)
    if err != nil {
        fmt.eprintfln("Error opening task file: %v", filename)
        os.exit(1)
    }
    defer os.close(file)

    // Read file bytes
    file_size: i64 = ---
    file_size, err = os.file_size(file)
    if err != nil {
        fmt.eprintln("Error reading file size")
        os.exit(1)
    }

    // Initialize arena allocator
    arena: mem.Arena
    arena_buffer := make([]byte, file_size)
    mem.arena_init(&arena, arena_buffer)
    arena_allocator := mem.arena_allocator(&arena)

    // Initialize CSV reader
    csv_reader: csv.Reader
    csv_reader.trim_leading_space  = true
    csv_reader.reuse_record        = true
    csv_reader.reuse_record_buffer = true
    csv.reader_init(&csv_reader, os.stream_from_handle(file))
    defer csv.reader_destroy(&csv_reader)

    // Read tasks
    tasks := make(map[string][dynamic]Task)
    for row, _ in csv.iterator_next(&csv_reader) {
        name, _ := strings.clone(row[0], arena_allocator)
        status := decode_status(row[1])
        category, _ := strings.clone(row[2], arena_allocator)
        due_date, _ := strings.clone(row[3], arena_allocator)

        task := Task{
            name=name,
            status=status,
            due_date=due_date,
        }

        if !(category in tasks) {
            tasks[category] = make([dynamic]Task)
        }
        append(&tasks[category], task)
    }

    return tasks, arena_buffer
}

/*
 * Saves tasks to the given file
 */
save_tasks :: proc(filename: string, tasks: map[string][dynamic]Task) {
    // Open file
    file, err := os.open(filename, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
    if err != nil {
        fmt.eprintfln("Error opening file: %v", filename)
        os.exit(1)
    }
    defer os.close(file)

    // Initialize CSV writer
    csv_writer: csv.Writer
    csv_writer.comma = ','
    csv_writer.use_crlf = false
    csv.writer_init(&csv_writer, os.stream_from_handle(file))

    // Write tasks
    task_buffer: [4]string
    for category in tasks {
        for task in tasks[category] {
            task_buffer[0] = task.name
            task_buffer[1] = encode_status(task.status)
            task_buffer[2] = category
            task_buffer[3] = task.due_date

            err := csv.write(&csv_writer, task_buffer[:])
            if err != nil {
                fmt.eprintln("Error saving tasks")
                os.exit(1)
            }
        }
    }

    // Check for any final errors
    err = csv.writer_flush(&csv_writer)
    if err != nil {
        fmt.eprintln("Error saving tasks")
        os.exit(1)
    }
}

/*
 * Display tasks from each category
 */
show :: proc(tasks: map[string][dynamic]Task, categories: [dynamic]string) {
    for category in categories {
        fmt.printfln("--- %s ---", category)
        for task in tasks[category] {
            if task.due_date == "" {
                fmt.printfln("name: %s, status: %s", task.name, task.status)
            } else {
                fmt.printfln("name: %s, status: %s, due_date: %s", task.name, task.status, task.due_date)
            }
        }
        fmt.println()
    }
}

/*
 * CLI application for managing personal tasks
 */
main :: proc() {
    // Check for CLI arguments
    if len(os.args) > 2 {
        fmt.eprintln("Too many arguments")
        os.exit(1)
    } else if len(os.args) == 2 && os.args[1] != "show" {
        fmt.eprintln("Invalid command given")
        os.exit(1)
    }

    // Set up input scanner
    scanner: bufio.Scanner
    stdin := os.stream_from_handle(os.stdin)
    bufio.scanner_init(&scanner, stdin, context.temp_allocator)
    defer free_all(context.temp_allocator)

    // Load task data
    tasks, arena_buffer := read_tasks(DATA_FILE)
    defer delete(tasks)
    defer delete(arena_buffer)

    // Get categories
    categories: [dynamic]string
    defer delete(categories)
    for category in tasks {
        append(&categories, category)
    }
    slice.sort(categories[:])

    // Start application
    fmt.println("=== Task Manager ===")

    // Check for quick show command
    if len(os.args) == 2 {
        show(tasks, categories)
        os.exit(0)
    }

    // Start application loop
    changed := false
    outer: for {
        // Read command from user input
        fmt.print("> ")
        if !bufio.scanner_scan(&scanner) {
            break outer
        }
        command := bufio.scanner_text(&scanner)

        // Execute command
        switch command {
        case "show":
            show(tasks, categories)
        case "add":
            // Get task fields from user input
            fmt.print("Name: ")
            if !bufio.scanner_scan(&scanner) {
                break outer
            }
            name := bufio.scanner_text(&scanner)

            fmt.print("Category: ")
            if !bufio.scanner_scan(&scanner) {
                break outer
            }
            category := bufio.scanner_text(&scanner)

            fmt.print("Due Date: ")
            if !bufio.scanner_scan(&scanner) {
                break outer
            }
            due_date := bufio.scanner_text(&scanner)

            // Create new category if needed
            index, found := slice.binary_search(categories[:], category)
            if !found {
                inject_at(&categories, index, category)
                tasks[category] = make([dynamic]Task)
            }

            // Add task
            task := Task{
                name=name,
                status="Not Started",
                due_date=due_date
            }
            append(&tasks[category], task)

            changed = true
        case "update":
            // Display categories
            index := 0
            for category in categories {
                fmt.println(index, category)
                index += 1
            }

            // Get tasks from a specific category
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_category_index: int = ---
            valid: bool = ---
            selected_category_index, valid = strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_category_index >= len(categories) {
                fmt.eprintln("Invalid index")
                os.exit(1)
            }
            selected_category := categories[selected_category_index]
            selected_tasks := tasks[selected_category]

            // Display task options
            index = 0
            fmt.printfln("--- %s ---", selected_category)
            for task in selected_tasks {
                if task.due_date == "" {
                    fmt.printfln("(%d) name: %s, status: %s", index, task.name, task.status)
                } else {
                    fmt.printfln("(%d) name: %s, status: %s, due_date: %s", index, task.name, task.status, task.due_date)
                }
                index += 1
            }

            // Select task to update
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_task_index: int = ---
            selected_task_index, valid = strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_task_index >= len(selected_tasks) {
                fmt.eprintln("Invalid index")
                os.exit(1)
            }
            selected_task := &selected_tasks[selected_task_index]

            // Get user update values
            fmt.print("key: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            key := bufio.scanner_text(&scanner)

            fmt.print("value: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            value := bufio.scanner_text(&scanner)

            // Update task
            switch key {
                case "name":
                    selected_task.name = value
                case "status":
                    selected_task.status = value
                case "category":
                    if value != selected_category {
                        // Check if the category exists
                        index, found := slice.binary_search(categories[:], value)
                        if !found {
                            inject_at(&categories, index, value)
                            tasks[value] = make([dynamic]Task)
                        }

                        // Add task to its new category
                        append(&tasks[value], selected_task^)

                        // Delete task entry from original category
                        if len(tasks[selected_category]) == 1 {
                            ordered_remove(&categories, selected_category_index)
                            delete(tasks[selected_category])
                            delete_key(&tasks, selected_category)
                        } else {
                            ordered_remove(&tasks[selected_category], selected_task_index)
                        }
                    }
                case "due_date":
                    selected_task.due_date = value
                case:
                    fmt.println("Invalid key")
                    os.exit(1)
            }

            changed = true
        case "delete":
            // Display categories
            index := 0
            for category in categories {
                fmt.println(index, category)
                index += 1
            }

            // Get tasks from a specific category
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            valid: bool = ---
            selected_category_index: int = ---
            selected_category_index, valid = strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_category_index >= len(categories) {
                fmt.eprintln("Invalid index")
                os.exit(1)
            }
            selected_category := categories[selected_category_index]
            selected_tasks := tasks[selected_category]

            // Display task options
            index = 0
            fmt.printfln("--- %s ---", categories[selected_category_index])
            for task in selected_tasks {
                if task.due_date == "" {
                    fmt.printfln("(%d) name: %s, status: %s", index, task.name, task.status)
                } else {
                    fmt.printfln("(%d) name: %s, status: %s, due_date: %s", index, task.name, task.status, task.due_date)
                }
                index += 1
            }

            // Select task to delete
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_task_index: int = ---
            selected_task_index, valid = strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_task_index >= len(selected_tasks) {
                fmt.eprintln("Invalid index")
                os.exit(1)
            }

            // Delete task
            ordered_remove(&tasks[selected_category], selected_task_index)
            if len(tasks[selected_category]) == 0 {
                delete_key(&tasks, selected_category)
                ordered_remove(&categories, selected_category_index)
            }

            changed = true
        case "start":
            // Display categories
            index := 0
            for category in categories {
                fmt.println(index, category)
                index += 1
            }

            // Get tasks from a specific category
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_index, valid := strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_index >= len(categories) {
                fmt.eprintln("Invalid index")
                os.exit(1)
            }
            selected_tasks := tasks[categories[selected_index]]

            // Display task options
            index = 0
            fmt.printfln("--- %s ---", categories[selected_index])
            for task in selected_tasks {
                if task.due_date == "" {
                    fmt.printfln("(%d) name: %s, status: %s", index, task.name, task.status)
                } else {
                    fmt.printfln("(%d) name: %s, status: %s, due_date: %s", index, task.name, task.status, task.due_date)
                }
                index += 1
            }

            // Select task to update
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_index, valid = strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_index >= len(selected_tasks) {
                fmt.eprintln("Invalid index")
                os.exit(1)
            }

            // Update task
            selected_tasks[selected_index].status = "In Progress"

            changed = true
        case "check":
            // Display categories
            index := 0
            for category in categories {
                fmt.println(index, category)
                index += 1
            }

            // Get tasks from a specific category
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_index, valid := strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_index >= len(categories) {
                fmt.eprintln("Invalid index")
                os.exit(1)
            }
            selected_tasks := tasks[categories[selected_index]]

            // Display task options
            index = 0
            fmt.printfln("--- %s ---", categories[selected_index])
            for task in selected_tasks {
                if task.due_date == "" {
                    fmt.printfln("(%d) name: %s, status: %s", index, task.name, task.status)
                } else {
                    fmt.printfln("(%d) name: %s, status: %s, due_date: %s", index, task.name, task.status, task.due_date)
                }
                index += 1
            }

            // Select task to update
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_index, valid = strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_index >= len(selected_tasks) {
                fmt.eprintln("Invalid index")
                os.exit(1)
            }

            // Update task
            selected_tasks[selected_index].status = "Complete"

            changed = true
        case "save":
            // Write changes
            if changed {
                save_tasks(DATA_FILE, tasks)
            }
            break outer
        case "quit":
            // Check for any unsaved changes
            if changed {
                resolved := false
                for !resolved {
                    fmt.print("Unsaved changes found. Are you sure you want to quit (y/n): ")
                    if !bufio.scanner_scan(&scanner) {
                        break
                    }
                    response := bufio.scanner_text(&scanner)

                    if response == "y" {
                        break outer
                    } else if response == "n" {
                        resolved = true
                    } else {
                        fmt.println("Invalid response.")
                    }
                }
            } else {
                break outer
            }
        case "":
        case:
            fmt.println("Invalid Command")
        }
    }

    // Check for scanner errors
    if err := bufio.scanner_error(&scanner); err != nil {
        fmt.eprintln("Scanner error:", err)
    }

    // Free task data
    for category in tasks {
        delete(tasks[category])
    }
}
