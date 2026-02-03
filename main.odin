package main

import "core:fmt"
import "core:mem"
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
MAX_FIELD_SIZE :: 255
MAX_CATEGORY_SIZE :: 255

/*
 * Decode status from file input
 */
decode_status :: proc "contextless" (number: u8) -> string {
    switch number {
    case u8(0):
        return "Not Started"
    case u8(1):
        return "In Progress"
    case u8(2):
        return "Complete"
    case:
        return ""
    }
}

/*
 * Encode status for file writing
 */
encode_status :: proc "contextless" (status: string) -> u8 {
    switch status {
    case "Not Started":
        return u8(0)
    case "In Progress":
        return u8(1)
    case "Complete":
        return u8(2)
    case:
        return u8(3)
    }
}

/*
 * Load task data
 */
read_tasks :: proc(filename: string) -> (map[string][dynamic]Task, []byte) {
    // Read all file contents into memory
    data, ok := os.read_entire_file(filename)
    if !ok {
        fmt.eprintfln("Error opening task file: %v", filename)
        os.exit(1)
    }
    tasks := make(map[string][dynamic]Task)

    // Iteratively read category and task entries
    start_ptr := raw_data(data)
    curr_ptr := start_ptr
    for mem.ptr_sub(curr_ptr, start_ptr) != len(data) {
        // Read number of tasks in current category
        num_entries := curr_ptr[0]
        curr_ptr = mem.ptr_offset(curr_ptr, 1)

        // Read category name
        category_str_len := cast(int) curr_ptr[0]
        category := strings.string_from_ptr(mem.ptr_offset(curr_ptr, 1), category_str_len)
        curr_ptr = mem.ptr_offset(curr_ptr, 1 + category_str_len)

        // Allocate memory for task entries
        tasks[category] = make([dynamic]Task, num_entries)
        category_tasks := &tasks[category]

        // Read tasks in category
        for i in 0..<num_entries {
            // Read status
            status := decode_status(curr_ptr[0])
            curr_ptr = mem.ptr_offset(curr_ptr, 1)

            // Read name
            name_length := cast(int) curr_ptr[0]
            name := strings.string_from_ptr(mem.ptr_offset(curr_ptr, 1), name_length)
            curr_ptr = mem.ptr_offset(curr_ptr, 1 + name_length)

            // Read due date
            due_date_length := cast(int) curr_ptr[0]
            due_date := strings.string_from_ptr(mem.ptr_offset(curr_ptr, 1), due_date_length)
            curr_ptr = mem.ptr_offset(curr_ptr, 1 + due_date_length)

            // Create task
            task := Task{
                name=name,
                status=status,
                due_date=due_date,
            }
            category_tasks[i] = task
        }
    }

    return tasks, data
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

    // Iteratively write category and task entries
    for category in tasks {
        // Write number of tasks in current category
        os.write_byte(file, u8(len(tasks[category])))

        // Write category name
        os.write_byte(file, u8(len(category)))
        os.write_string(file, category)

        // Write tasks in category
        for task in tasks[category] {
            // Write status
            os.write_byte(file, encode_status(task.status))

            // Write name
            os.write_byte(file, u8(len(task.name)))
            os.write_string(file, task.name)

            // Write due date
            os.write_byte(file, u8(len(task.due_date)))
            os.write_string(file, task.due_date)
        }
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
    tasks, data := read_tasks(DATA_FILE)
    defer delete(tasks)
    defer delete(data)

    // Get categories
    categories := make([dynamic]string, len(tasks))
    defer delete(categories)
    i := 0
    for category in tasks {
        categories[i] = category
        i += 1
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
            break
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
                break
            }
            name := bufio.scanner_text(&scanner)
            if len(name) > MAX_FIELD_SIZE {
                fmt.eprintln("Name cannot exceed 255 characters")
                break
            }

            fmt.print("Category: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            category := bufio.scanner_text(&scanner)
            if len(category) > MAX_FIELD_SIZE {
                fmt.eprintln("Category cannot exceed 255 characters")
                break
            } else if category in tasks && len(tasks[category]) == MAX_CATEGORY_SIZE {
                fmt.eprintln("A single category cannot store more than 255 tasks")
                break
            }

            fmt.print("Due Date: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            due_date := bufio.scanner_text(&scanner)
            if len(due_date) > MAX_FIELD_SIZE {
                fmt.eprintln("Due date cannot exceed 255 characters")
                break
            }

            // Create new category if needed
            index, found := slice.binary_search(categories[:], category)
            if !found {
                inject_at(&categories, index, category)
                tasks[category] = make([dynamic]Task, 0, 1)
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
                break
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
                break
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
            successful_update: bool = ---
            switch key {
            case "name":
                if selected_task.name == value {
                    successful_update = false
                } else if len(value) > MAX_FIELD_SIZE {
                    fmt.eprintln("Name cannot exceed 255 characters")
                    successful_update = false
                } else {
                    selected_task.name = value
                    successful_update = true
                }
            case "status":
                if value != "Not Started" && value != "In Progress" && value != "Complete" {
                    fmt.eprintln("Invalid status. Supported values are: \"Not Started\", \"In Progress\", and \"Complete\"")
                    successful_update = false
                } else if selected_task.status == value {
                    successful_update = false
                } else {
                    selected_task.status = value
                    successful_update = true
                }
            case "category":
                if value == selected_category {
                    successful_update = false
                } else if len(value) > MAX_FIELD_SIZE {
                    fmt.eprintln("Category cannot exceed 255 characters")
                    successful_update = false
                } else if value in tasks && len(tasks[value]) == MAX_CATEGORY_SIZE {
                    fmt.eprintln("A single category cannot store more than 255 tasks")
                    successful_update = false
                } else {
                    // Check if the category exists
                    index, found := slice.binary_search(categories[:], value)
                    if !found {
                        inject_at(&categories, index, value)
                        tasks[value] = make([dynamic]Task, 0, 1)
                        if index < selected_category_index {
                            selected_category_index += 1
                        }
                    }

                    // Add task to its new category
                    append(&tasks[value], selected_task^)

                    // Delete task entry from original category
                    if len(tasks[selected_category]) == 1 {
                        delete(tasks[selected_category])
                        delete_key(&tasks, selected_category)
                        ordered_remove(&categories, selected_category_index)
                    } else {
                        ordered_remove(&tasks[selected_category], selected_task_index)
                    }

                    successful_update = true
                }
            case "due_date":
                if selected_task.due_date == value {
                    successful_update = false
                } else if len(value) > MAX_FIELD_SIZE {
                    fmt.eprintln("Due date cannot exceed 255 characters")
                    successful_update = false
                } else {
                    selected_task.due_date = value
                    successful_update = true
                }
            case:
                fmt.println("Invalid key")
                successful_update = false
            }

            if successful_update {
                changed = true
            }
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
                break
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
                break
            }

            // Delete task
            ordered_remove(&tasks[selected_category], selected_task_index)
            if len(tasks[selected_category]) == 0 {
                delete(tasks[selected_category])
                delete_key(&tasks, selected_category)
                ordered_remove(&categories, selected_category_index)
            }

            changed = true
        case "delete many":
            // Display categories
            for category, index in categories {
                fmt.println(index, category)
            }

            // Get tasks from a specific category
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_category_index, valid := strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_category_index >= len(categories) {
                fmt.eprintln("Invalid index")
                break
            }
            selected_category := categories[selected_category_index]
            selected_tasks := tasks[selected_category]

            // Display task options
            fmt.printfln("--- %s ---", selected_category)
            for task, index in selected_tasks {
                if task.due_date == "" {
                    fmt.printfln("(%d) name: %s, status: %s", index, task.name, task.status)
                } else {
                    fmt.printfln("(%d) name: %s, status: %s, due_date: %s", index, task.name, task.status, task.due_date)
                }
            }

            // Select tasks to delete
            removal_indices := make([dynamic]int, 0, len(selected_tasks))
            defer delete(removal_indices)
            for {
                // Get task index
                fmt.print("Enter index: ")
                if !bufio.scanner_scan(&scanner) {
                    break
                }
                value := bufio.scanner_text(&scanner)

                // Check for termination
                if value == "done" {
                    break
                }

                // Validate index value
                selected_task_index, valid := strconv.parse_int(value)
                if !valid || selected_task_index >= len(selected_tasks) {
                    fmt.eprintln("Invalid index")
                    clear(&removal_indices)
                    break
                }

                // Validate uniqueness
                insertion_index, found := slice.binary_search(removal_indices[:], selected_task_index)
                if found {
                    fmt.eprintln("Duplicate index detected")
                    clear(&removal_indices)
                    break
                }

                // Add task index for removal
                inject_at(&removal_indices, insertion_index, selected_task_index)
            }

            // If provided indices are valid start removing
            if len(removal_indices) > 0 {
                // Remove tasks from category
                #reverse for index in removal_indices {
                    ordered_remove(&tasks[selected_category], index)
                }

                // Delete category if no tasks remain
                if len(tasks[selected_category]) == 0 {
                    delete(tasks[selected_category])
                    delete_key(&tasks, selected_category)
                    ordered_remove(&categories, selected_category_index)
                }

                changed = true
            }
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
                break
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
                break
            }

            // Update task
            if selected_tasks[selected_index].status != "In Progress" {
                selected_tasks[selected_index].status = "In Progress"
                changed = true
            }
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
                break
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
                break
            }

            // Update task
            if selected_tasks[selected_index].status != "Complete" {
                selected_tasks[selected_index].status = "Complete"
                changed = true
            }
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
                    fmt.print("Unsaved changes found. Are you sure you want to quit? (y/n): ")
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
