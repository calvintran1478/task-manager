package main

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:strconv"
import "core:slice"
import "core:bufio"
import "core:os"
import "base:runtime"

Task :: struct {
    name: string,
    status: u8,
    today: bool,
    due_date: string
}

DATA_FILE :: ""
MAX_FIELD_SIZE :: 255
MAX_CATEGORY_SIZE :: 120
MAX_NUM_CATEGORIES :: 50
MAX_TASK_SELECTION_SIZE :: MAX_NUM_CATEGORIES * MAX_CATEGORY_SIZE

@(rodata)
status_strings: [4]string = {"Not Started", "Queue", "In Progress", "Complete"}

/*
 * Encode status for file writing
 */
encode_status :: proc "contextless" (status: string) -> u8 {
    switch status {
    case "Not Started":
        return u8(0)
    case "Queue":
        return u8(1)
    case "In Progress":
        return u8(2)
    case "Complete":
        return u8(3)
    case:
        return u8(4)
    }
}

/*
 * Load task data in the form of dynamic arrays
 */
read_tasks_dynamic :: proc(filename: string, tasks: ^[dynamic][dynamic]Task, categories: ^[dynamic]string) -> []byte {
    // Read all file contents into memory
    data, err := os.read_entire_file_from_path(filename, context.allocator)
    if err != nil {
        fmt.eprintfln("Error opening task file: %v", filename)
        os.exit(1)
    }

    // Iteratively read category and task entries
    start_ptr := raw_data(data)
    curr_ptr := start_ptr
    category_index := 0
    for mem.ptr_sub(curr_ptr, start_ptr) != len(data) {
        // Read number of tasks in current category
        num_entries := curr_ptr[0]
        curr_ptr = mem.ptr_offset(curr_ptr, 1)

        // Read category name
        category_str_len := cast(int) curr_ptr[0]
        category := strings.string_from_ptr(mem.ptr_offset(curr_ptr, 1), category_str_len)
        curr_ptr = mem.ptr_offset(curr_ptr, 1 + category_str_len)
        #no_bounds_check categories^[category_index] = category

        // Allocate memory for task entries
        category_tasks := make([dynamic]Task, num_entries)
        #no_bounds_check tasks^[category_index] = category_tasks
        category_index += 1

        // Read tasks in category
        for i in 0..<num_entries {
            // Read status
            status := curr_ptr[0]
            curr_ptr = mem.ptr_offset(curr_ptr, 1)

            // Read "today" status
            today := bool(curr_ptr[0])
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
            category_tasks[i] = Task{
                name=name,
                status=status,
                today=today,
                due_date=due_date,
            }
        }
    }

    // Set lengths of tasks and categories
    (^runtime.Raw_Dynamic_Array)(tasks).len = category_index
    (^runtime.Raw_Dynamic_Array)(categories).len = category_index

    return data
}

/*
 * Load task data in the form of slices
 */
read_tasks_fixed :: proc(filename: string, tasks: ^[dynamic][]Task, categories: ^[dynamic] string, task_buffer: []Task) -> []byte {
    // Read all file contents into memory
    data, err := os.read_entire_file_from_path(filename, context.allocator)
    if err != nil {
        fmt.eprintfln("Error opening task file: %v", filename)
        os.exit(1)
    }

    // Iteratively read category and task entries
    start_ptr := raw_data(data)
    curr_ptr := start_ptr
    num_tasks, category_index := 0, 0
    for mem.ptr_sub(curr_ptr, start_ptr) != len(data) {
        // Read number of tasks in current category
        num_entries := curr_ptr[0]
        curr_ptr = mem.ptr_offset(curr_ptr, 1)

        // Read category name
        category_str_len := cast(int) curr_ptr[0]
        category := strings.string_from_ptr(mem.ptr_offset(curr_ptr, 1), category_str_len)
        curr_ptr = mem.ptr_offset(curr_ptr, 1 + category_str_len)
        #no_bounds_check categories^[category_index] = category

        // Set up category task entries
        category_tasks := task_buffer[num_tasks:(num_tasks + cast(int) num_entries)]
        #no_bounds_check tasks^[category_index] = category_tasks
        category_index += 1

        // Read tasks in category
        for i in 0..<num_entries {
            // Read status
            status := curr_ptr[0]
            curr_ptr = mem.ptr_offset(curr_ptr, 1)

            // Read "today" status
            today := bool(curr_ptr[0])
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
            category_tasks[i] = Task{
                name=name,
                status=status,
                today=today,
                due_date=due_date,
            }
        }
        num_tasks += cast(int) num_entries
    }

    // Set lengths of tasks and categories
    (^runtime.Raw_Dynamic_Array)(tasks).len = category_index
    (^runtime.Raw_Dynamic_Array)(categories).len = category_index

    return data
}

read_tasks :: proc{read_tasks_dynamic, read_tasks_fixed}

/*
 * Saves tasks to the given file
 */
save_tasks_dynamic :: proc(filename: string, tasks: [dynamic][dynamic]Task, categories: [dynamic]string) {
    // Open file
    file, err := os.open(filename, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
    if err != nil {
        fmt.eprintfln("Error opening file: %v", filename)
        os.exit(1)
    }
    defer os.close(file)

    // Iteratively write category and task entries
    for category, i in categories {
        // Write number of tasks in current category
        os.write_byte(file, u8(len(tasks[i])))

        // Write category name
        os.write_byte(file, u8(len(category)))
        os.write_string(file, category)

        // Write tasks in category
        for task in tasks[i] {
            // Write status
            os.write_byte(file, task.status)

            // Write "today" status
            os.write_byte(file, u8(task.today))

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
 * Saves tasks to the given file
 */
save_tasks_fixed :: proc(filename: string, tasks: [dynamic][]Task, categories: [dynamic] string) {
    // Open file
    file, err := os.open(filename, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
    if err != nil {
        fmt.eprintfln("Error opening file: %v", filename)
        os.exit(1)
    }
    defer os.close(file)

    // Iteratively write category and task entries
    for category, i in categories {
        // Write number of tasks in current category
        os.write_byte(file, u8(len(tasks[i])))

        // Write category name
        os.write_byte(file, u8(len(category)))
        os.write_string(file, category)

        // Write tasks in category
        for task in tasks[i] {
            // Write status
            os.write_byte(file, task.status)

            // Write "today" status
            os.write_byte(file, u8(task.today))

            // Write name
            os.write_byte(file, u8(len(task.name)))
            os.write_string(file, task.name)

            // Write due date
            os.write_byte(file, u8(len(task.due_date)))
            os.write_string(file, task.due_date)
        }
    }
}

save_tasks :: proc{save_tasks_dynamic, save_tasks_fixed}

/*
 * CLI application for managing personal tasks
 */
main :: proc() {
    // Check for CLI arguments
    if len(os.args) > 3 {
        fmt.eprintln("Too many arguments")
        os.exit(1)
    }

    // Set up input scanner
    scanner: bufio.Scanner
    stdin := os.to_stream(os.stdin)
    bufio.scanner_init(&scanner, stdin, context.temp_allocator)
    defer {
        if err := bufio.scanner_error(&scanner); err != nil {
            fmt.eprintln("Scanner error:", err)
        }
        free_all(context.temp_allocator)
    }

    // Initialize stack-allocated buffer for storing categories
    category_buffer: [MAX_NUM_CATEGORIES]string = ---
    categories := mem.buffer_from_slice(category_buffer[:])

    // Check for quick commands
    if len(os.args) == 3 {
        if os.args[1] == "set" && os.args[2] == "today" {
            // Initialize stack-allocated buffers for storing task data
            tasks_list_buffer: [MAX_NUM_CATEGORIES][]Task = ---
            task_buffer: [MAX_TASK_SELECTION_SIZE]Task = ---
            tasks := mem.buffer_from_slice(tasks_list_buffer[:])

            // Load task data from data file
            data := read_tasks(DATA_FILE, &tasks, &categories, task_buffer[:])
            defer delete(data)

            // Display tasks
            fmt.println("=== Task Manager ===")
            task_index := 0
            for category, i in categories {
                fmt.printfln("--- %s ---", category)
                for &task in tasks[i] {
                    if task.due_date == "" {
                        fmt.printfln("(%d) name: %s, status: %s", task_index, task.name, status_strings[task.status])
                    } else {
                        fmt.printfln("(%d) name: %s, status: %s, due_date: %s", task_index, task.name, status_strings[task.status], task.due_date)
                    }
                    task.today = false
                    task_index += 1
                }
                fmt.println()
            }

            // Select tasks to add for today
            indices_buffer: [MAX_TASK_SELECTION_SIZE]int = ---
            indices := mem.buffer_from_slice(indices_buffer[:])
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
                if !valid || selected_task_index < 0 || selected_task_index >= task_index {
                    fmt.eprintln("Invalid index")
                    clear(&indices)
                    break
                }

                // Validate uniqueness
                insertion_index, found := slice.binary_search(indices[:], selected_task_index)
                if found {
                    fmt.eprintln("Duplicate index detected")
                    clear(&indices)
                    break
                }

                // Add task index for updating
                inject_at(&indices, insertion_index, selected_task_index)
            }

            // If provided indices are valid start updating
            if len(indices) > 0 {
                for index in indices {
                    task_buffer[index].today = true
                }
            }

            // Update tasks
            save_tasks(DATA_FILE, tasks, categories)
        } else {
            fmt.eprintln("Invalid command given")
            os.exit(1)
        }
        os.exit(0)
    }

    if len(os.args) == 2 {
        switch os.args[1] {
        case "add":
            // Initialize stack-allocated buffers for storing task data
            tasks_list_buffer: [MAX_NUM_CATEGORIES][dynamic]Task = ---
            tasks := mem.buffer_from_slice(tasks_list_buffer[:])

            // Load task data from data file
            data := read_tasks(DATA_FILE, &tasks, &categories)
            defer {
                for i in 0..<len(tasks) {
                    delete(tasks[i])
                }
                delete(data)
            }

            // Get task fields from user input
            fmt.print("Name: ")
            if !bufio.scanner_scan(&scanner) {
                os.exit(1)
            }
            name := bufio.scanner_text(&scanner)
            if len(name) > MAX_FIELD_SIZE {
                fmt.eprintln("Name cannot exceed 255 characters")
                os.exit(1)
            }

            fmt.print("Category: ")
            if !bufio.scanner_scan(&scanner) {
                os.exit(1)
            }
            category := bufio.scanner_text(&scanner)
            if len(category) > MAX_FIELD_SIZE {
                fmt.eprintln("Category cannot exceed 255 characters")
                os.exit(1)
            }
            index, found := slice.binary_search(categories[:], category)
            if found && len(tasks[index]) == MAX_CATEGORY_SIZE {
                fmt.eprintln("A single category cannot store more than 120 tasks")
                os.exit(1)
            } else if !found && len(tasks) == MAX_NUM_CATEGORIES {
                fmt.eprintln("Cannot have more than 50 categories")
                os.exit(1)
            }

            fmt.print("Due Date: ")
            if !bufio.scanner_scan(&scanner) {
                os.exit(1)
            }
            due_date := bufio.scanner_text(&scanner)
            if len(due_date) > MAX_FIELD_SIZE {
                fmt.eprintln("Due date cannot exceed 255 characters")
                os.exit(1)
            }

            // Create task
            task := Task{
                name=name,
                status=u8(0),
                today=false,
                due_date=due_date
            }

            // Add task under its specified category
            if found {
                append(&tasks[index], task)
            } else {
                inject_at(&categories, index, category)
                inject_at(&tasks, index, make([dynamic]Task, 1, 1))
                tasks[index][0] = task
            }

            // Save task
            save_tasks(DATA_FILE, tasks, categories)
        case "addt":
            // Initialize stack-allocated buffers for storing task data
            tasks_list_buffer: [MAX_NUM_CATEGORIES][dynamic]Task = ---
            tasks := mem.buffer_from_slice(tasks_list_buffer[:])

            // Load task data from data file
            data := read_tasks(DATA_FILE, &tasks, &categories)
            defer {
                for i in 0..<len(tasks) {
                    delete(tasks[i])
                }
                delete(data)
            }

            // Get task fields from user input
            fmt.print("Name: ")
            if !bufio.scanner_scan(&scanner) {
                os.exit(1)
            }
            name := bufio.scanner_text(&scanner)
            if len(name) > MAX_FIELD_SIZE {
                fmt.eprintln("Name cannot exceed 255 characters")
                os.exit(1)
            }

            fmt.print("Category: ")
            if !bufio.scanner_scan(&scanner) {
                os.exit(1)
            }
            category := bufio.scanner_text(&scanner)
            if len(category) > MAX_FIELD_SIZE {
                fmt.eprintln("Category cannot exceed 255 characters")
                os.exit(1)
            }
            index, found := slice.binary_search(categories[:], category)
            if found && len(tasks[index]) == MAX_CATEGORY_SIZE {
                fmt.eprintln("A single category cannot store more than 120 tasks")
                os.exit(1)
            } else if !found && len(tasks) == MAX_NUM_CATEGORIES {
                fmt.eprintln("Cannot have more than 50 categories")
                os.exit(1)
            }

            fmt.print("Due Date: ")
            if !bufio.scanner_scan(&scanner) {
                os.exit(1)
            }
            due_date := bufio.scanner_text(&scanner)
            if len(due_date) > MAX_FIELD_SIZE {
                fmt.eprintln("Due date cannot exceed 255 characters")
                os.exit(1)
            }

            // Create task
            task := Task{
                name=name,
                status=u8(0),
                today=true,
                due_date=due_date
            }

            // Add task under its specified category
            if found {
                append(&tasks[index], task)
            } else {
                inject_at(&categories, index, category)
                inject_at(&tasks, index, make([dynamic]Task, 1, 1))
                tasks[index][0] = task
            }

            // Save task
            save_tasks(DATA_FILE, tasks, categories)
        case "show":
            // Initialize stack-allocated buffers for storing task data
            tasks_list_buffer: [MAX_NUM_CATEGORIES][]Task = ---
            task_buffer: [MAX_TASK_SELECTION_SIZE]Task = ---
            tasks := mem.buffer_from_slice(tasks_list_buffer[:])

            // Load task data from data file
            data := read_tasks(DATA_FILE, &tasks, &categories, task_buffer[:])
            defer delete(data)

            // Display tasks
            fmt.println("=== Task Manager ===")
            for category, i in categories {
                fmt.printfln("--- %s ---", category)
                for task in tasks[i] {
                    if task.due_date == "" {
                        fmt.printfln("name: %s, status: %s", task.name, status_strings[task.status])
                    } else {
                        fmt.printfln("name: %s, status: %s, due_date: %s", task.name, status_strings[task.status], task.due_date)
                    }
                }
                fmt.println()
            }
        case "today":
            // Initialize stack-allocated buffers for storing task data
            tasks_list_buffer: [MAX_NUM_CATEGORIES][]Task = ---
            task_buffer: [MAX_TASK_SELECTION_SIZE]Task = ---
            tasks := mem.buffer_from_slice(tasks_list_buffer[:])

            // Load task data from data file
            data := read_tasks(DATA_FILE, &tasks, &categories, task_buffer[:])
            defer delete(data)

            // Display tasks
            fmt.println("=== Task Manager ===")
            for category, i in categories {
                // Check if category has at least one task today
                category_tasks := tasks[i]
                start_index, j := -1, 0
                for start_index == -1 && j < len(category_tasks) {
                    if category_tasks[j].today {
                        start_index = j
                    }
                    j += 1
                }

                // Print category if at least one task was found
                if start_index != -1 {
                    fmt.printfln("--- %s ---", category)
                    first_task := category_tasks[start_index]
                    if first_task.due_date == "" {
                        fmt.printfln("name: %s, status: %s", first_task.name, status_strings[first_task.status])
                    } else {
                        fmt.printfln("name: %s, status: %s, due_date: %s", first_task.name, status_strings[first_task.status], first_task.due_date)
                    }

                    for j in (start_index + 1)..<len(category_tasks) {
                        task := category_tasks[j]
                        if task.today {
                            if task.due_date == "" {
                                fmt.printfln("name: %s, status: %s", task.name, status_strings[task.status])
                            } else {
                                fmt.printfln("name: %s, status: %s, due_date: %s", task.name, status_strings[task.status], task.due_date)
                            }
                        }
                    }
                    fmt.println()
                }
            }
        case "queue":
            // Initialize stack-allocated buffers for storing task data
            tasks_list_buffer: [MAX_NUM_CATEGORIES][]Task = ---
            task_buffer: [MAX_TASK_SELECTION_SIZE]Task = ---
            tasks := mem.buffer_from_slice(tasks_list_buffer[:])

            // Load task data from data file
            data := read_tasks(DATA_FILE, &tasks, &categories, task_buffer[:])
            defer delete(data)

            // Display tasks
            fmt.println("=== Task Manager ===")
            task_index := 0
            for category, i in categories {
                fmt.printfln("--- %s ---", category)
                for task in tasks[i] {
                    if task.due_date == "" {
                        fmt.printfln("(%d) name: %s, status: %s", task_index, task.name, status_strings[task.status])
                    } else {
                        fmt.printfln("(%d) name: %s, status: %s, due_date: %s", task_index, task.name, status_strings[task.status], task.due_date)
                    }
                    task_index += 1
                }
                fmt.println()
            }

            // Select task to update
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_index, valid := strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_index < 0 || selected_index >= task_index {
                fmt.eprintln("Invalid index")
                break
            }

            // Update task
            if task_buffer[selected_index].status != u8(1) {
                task_buffer[selected_index].status = u8(1)
                save_tasks(DATA_FILE, tasks, categories)
            }
        case "start":
            // Initialize stack-allocated buffers for storing task data
            tasks_list_buffer: [MAX_NUM_CATEGORIES][]Task = ---
            task_buffer: [MAX_TASK_SELECTION_SIZE]Task = ---
            tasks := mem.buffer_from_slice(tasks_list_buffer[:])

            // Load task data from data file
            data := read_tasks(DATA_FILE, &tasks, &categories, task_buffer[:])
            defer delete(data)

            // Display tasks
            fmt.println("=== Task Manager ===")
            task_index := 0
            for category, i in categories {
                fmt.printfln("--- %s ---", category)
                for task in tasks[i] {
                    if task.due_date == "" {
                        fmt.printfln("(%d) name: %s, status: %s", task_index, task.name, status_strings[task.status])
                    } else {
                        fmt.printfln("(%d) name: %s, status: %s, due_date: %s", task_index, task.name, status_strings[task.status], task.due_date)
                    }
                    task_index += 1
                }
                fmt.println()
            }

            // Select task to update
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_index, valid := strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_index < 0 || selected_index >= task_index {
                fmt.eprintln("Invalid index")
                break
            }

            // Update task
            if task_buffer[selected_index].status != u8(2) {
                task_buffer[selected_index].status = u8(2)
                save_tasks(DATA_FILE, tasks, categories)
            }
        case "check":
            // Initialize stack-allocated buffers for storing task data
            tasks_list_buffer: [MAX_NUM_CATEGORIES][]Task = ---
            task_buffer: [MAX_TASK_SELECTION_SIZE]Task = ---
            tasks := mem.buffer_from_slice(tasks_list_buffer[:])

            // Load task data from data file
            data := read_tasks(DATA_FILE, &tasks, &categories, task_buffer[:])
            defer delete(data)

            // Display tasks
            fmt.println("=== Task Manager ===")
            task_index := 0
            for category, i in categories {
                fmt.printfln("--- %s ---", category)
                for &task in tasks[i] {
                    if task.due_date == "" {
                        fmt.printfln("(%d) name: %s, status: %s", task_index, task.name, status_strings[task.status])
                    } else {
                        fmt.printfln("(%d) name: %s, status: %s, due_date: %s", task_index, task.name, status_strings[task.status], task.due_date)
                    }
                    task_index += 1
                }
                fmt.println()
            }

            // Select task to update
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_index, valid := strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_index < 0 || selected_index >= task_index {
                fmt.eprintln("Invalid index")
                break
            }

            // Update task
            if task_buffer[selected_index].status != u8(3) {
                task_buffer[selected_index].status = u8(3)
                save_tasks(DATA_FILE, tasks, categories)
            }
        case:
            fmt.eprintln("Invalid command given")
            os.exit(1)
        }
        os.exit(0)
    }

    // Initialize stack-allocated buffers for storing task data
    tasks_list_buffer: [MAX_NUM_CATEGORIES][dynamic]Task = ---
    tasks := mem.buffer_from_slice(tasks_list_buffer[:])

    // Load task data from data file
    data := read_tasks(DATA_FILE, &tasks, &categories)
    defer {
        for i in 0..<len(tasks) {
            delete(tasks[i])
        }
        delete(data)
    }

    // Display title
    fmt.println("=== Task Manager ===")

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
            for category, i in categories {
                fmt.printfln("--- %s ---", category)
                for task in tasks[i] {
                    if task.due_date == "" {
                        fmt.printfln("name: %s, status: %s", task.name, status_strings[task.status])
                    } else {
                        fmt.printfln("name: %s, status: %s, due_date: %s", task.name, status_strings[task.status], task.due_date)
                    }
                }
                fmt.println()
            }
        case "today":
            for category, i in categories {
                // Check if category has at least one task today
                category_tasks := tasks[i]
                start_index, j := -1, 0
                for start_index == -1 && j < len(category_tasks) {
                    if category_tasks[j].today {
                        start_index = j
                    }
                    j += 1
                }

                // Print category if at least one task was found
                if start_index != -1 {
                    fmt.printfln("--- %s ---", category)
                    first_task := category_tasks[start_index]
                    if first_task.due_date == "" {
                        fmt.printfln("name: %s, status: %s", first_task.name, status_strings[first_task.status])
                    } else {
                        fmt.printfln("name: %s, status: %s, due_date: %s", first_task.name, status_strings[first_task.status], first_task.due_date)
                    }

                    for j in (start_index + 1)..<len(category_tasks) {
                        task := category_tasks[j]
                        if task.today {
                            if task.due_date == "" {
                                fmt.printfln("name: %s, status: %s", task.name, status_strings[task.status])
                            } else {
                                fmt.printfln("name: %s, status: %s, due_date: %s", task.name, status_strings[task.status], task.due_date)
                            }
                        }
                    }
                    fmt.println()
                }
            }
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
            }
            index, found := slice.binary_search(categories[:], category)
            if found && len(tasks[index]) == MAX_CATEGORY_SIZE {
                fmt.eprintln("A single category cannot store more than 120 tasks")
                break
            } else if !found && len(categories) == MAX_NUM_CATEGORIES {
                fmt.eprintln("Cannot have more than 50 categories")
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

            // Create task
            task := Task{
                name=name,
                status=u8(0),
                today=false,
                due_date=due_date
            }

            // Add task under its specified category
            if found {
                append(&tasks[index], task)
            } else {
                inject_at(&categories, index, category)
                inject_at(&tasks, index, make([dynamic]Task, 1, 1))
                tasks[index][0] = task
            }

            changed = true
        case "addt":
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
            }
            index, found := slice.binary_search(categories[:], category)
            if found && len(tasks[index]) == MAX_CATEGORY_SIZE {
                fmt.eprintln("A single category cannot store more than 120 tasks")
                break
            } else if !found && len(categories) == MAX_NUM_CATEGORIES {
                fmt.eprintln("Cannot have more than 50 categories")
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

            // Create task
            task := Task{
                name=name,
                status=u8(0),
                today=true,
                due_date=due_date
            }

            // Add task under its specified category
            if found {
                append(&tasks[index], task)
            } else {
                inject_at(&categories, index, category)
                inject_at(&tasks, index, make([dynamic]Task, 1, 1))
                tasks[index][0] = task
            }

            changed = true
        case "update":
            // Display categories
            for category, index in categories {
                fmt.println(index, category)
            }

            // Get tasks from a specific category
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_category_index: int = ---
            valid: bool = ---
            selected_category_index, valid = strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_category_index < 0 || selected_category_index >= len(categories) {
                fmt.eprintln("Invalid index")
                break
            }
            selected_category := categories[selected_category_index]
            selected_tasks := tasks[selected_category_index]

            // Display task options
            fmt.printfln("--- %s ---", selected_category)
            for task, index in selected_tasks {
                if task.due_date == "" {
                    fmt.printfln("(%d) name: %s, status: %s", index, task.name, status_strings[task.status])
                } else {
                    fmt.printfln("(%d) name: %s, status: %s, due_date: %s", index, task.name, status_strings[task.status], task.due_date)
                }
            }

            // Select task to update
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_task_index: int = ---
            selected_task_index, valid = strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_task_index < 0 || selected_task_index >= len(selected_tasks) {
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
                if value != "Not Started" && value != "Queue" && value != "In Progress" && value != "Complete" {
                    fmt.eprintln("Invalid status. Supported values are: \"Not Started\", \"Queue\", \"In Progress\", and \"Complete\"")
                    successful_update = false
                } else if selected_task.status == encode_status(value) {
                    successful_update = false
                } else {
                    selected_task.status = encode_status(value)
                    successful_update = true
                }
            case "today":
                if value != "0" && value != "1" {
                    fmt.eprintln("Invalid value. Supported values are 0 and 1.")
                    successful_update = false
                } else {
                    selected_task.today = (value == "1")
                    successful_update = true
                }
            case "category":
                if value == selected_category {
                    successful_update = false
                } else if len(value) > MAX_FIELD_SIZE {
                    fmt.eprintln("Category cannot exceed 255 characters")
                    successful_update = false
                }
                index, found := slice.binary_search(categories[:], value)
                if found && len(tasks[index]) == MAX_CATEGORY_SIZE {
                    fmt.eprintln("A single category cannot store more than 120 tasks")
                    successful_update = false
                } else if !found && len(categories) == MAX_NUM_CATEGORIES {
                    fmt.eprintln("Cannot have more than 50 categories")
                    successful_update = false
                } else {
                    // Check if the category exists
                    if !found {
                        inject_at(&categories, index, value)
                        inject_at(&tasks, index, make([dynamic]Task, 0, 1))
                        if index < selected_category_index {
                            selected_category_index += 1
                        }
                    }

                    // Add task to its new category
                    append(&tasks[index], selected_task^)

                    // Delete task entry from original category
                    if len(tasks[selected_category_index]) == 1 {
                        delete(tasks[selected_category_index])
                        ordered_remove(&tasks, selected_category_index)
                        ordered_remove(&categories, selected_category_index)
                    } else {
                        ordered_remove(&tasks[selected_category_index], selected_task_index)
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
            for category, index in categories {
                fmt.println(index, category)
            }

            // Get tasks from a specific category
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            valid: bool = ---
            selected_category_index: int = ---
            selected_category_index, valid = strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_category_index < 0 || selected_category_index >= len(categories) {
                fmt.eprintln("Invalid index")
                break
            }
            selected_category := categories[selected_category_index]
            selected_tasks := tasks[selected_category_index]

            // Display task options
            fmt.printfln("--- %s ---", selected_category)
            for task, index in selected_tasks {
                if task.due_date == "" {
                    fmt.printfln("(%d) name: %s, status: %s", index, task.name, status_strings[task.status])
                } else {
                    fmt.printfln("(%d) name: %s, status: %s, due_date: %s", index, task.name, status_strings[task.status], task.due_date)
                }
            }

            // Select task to delete
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_task_index: int = ---
            selected_task_index, valid = strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_task_index < 0 || selected_task_index >= len(selected_tasks) {
                fmt.eprintln("Invalid index")
                break
            }

            // Delete task
            ordered_remove(&tasks[selected_category_index], selected_task_index)
            if len(tasks[selected_category_index]) == 0 {
                delete(tasks[selected_category_index])
                ordered_remove(&tasks, selected_category_index)
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
            if !valid || selected_category_index < 0 || selected_category_index >= len(categories) {
                fmt.eprintln("Invalid index")
                break
            }
            selected_category := categories[selected_category_index]
            selected_tasks := tasks[selected_category_index]

            // Display task options
            fmt.printfln("--- %s ---", selected_category)
            for task, index in selected_tasks {
                if task.due_date == "" {
                    fmt.printfln("(%d) name: %s, status: %s", index, task.name, status_strings[task.status])
                } else {
                    fmt.printfln("(%d) name: %s, status: %s, due_date: %s", index, task.name, status_strings[task.status], task.due_date)
                }
            }

            // Select tasks to delete
            removal_indices_buffer: [MAX_CATEGORY_SIZE]int = ---
            removal_indices := mem.buffer_from_slice(removal_indices_buffer[:])
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
                if !valid || selected_task_index < 0 || selected_task_index >= len(selected_tasks) {
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
                    ordered_remove(&tasks[selected_category_index], index)
                }

                // Delete category if no tasks remain
                if len(tasks[selected_category_index]) == 0 {
                    delete(tasks[selected_category_index])
                    ordered_remove(&tasks, selected_category_index)
                    ordered_remove(&categories, selected_category_index)
                }

                changed = true
            }
        case "queue":
            // Display categories
            for category, index in categories {
                fmt.println(index, category)
            }

            // Get tasks from a specific category
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_index, valid := strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_index < 0 || selected_index >= len(categories) {
                fmt.eprintln("Invalid index")
                break
            }
            selected_tasks := tasks[selected_index]

            // Display task options
            fmt.printfln("--- %s ---", categories[selected_index])
            for task, index in selected_tasks {
                if task.due_date == "" {
                    fmt.printfln("(%d) name: %s, status: %s", index, task.name, status_strings[task.status])
                } else {
                    fmt.printfln("(%d) name: %s, status: %s, due_date: %s", index, task.name, status_strings[task.status], task.due_date)
                }
            }

            // Select task to update
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_index, valid = strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_index < 0 || selected_index >= len(selected_tasks) {
                fmt.eprintln("Invalid index")
                break
            }

            // Update task
            if selected_tasks[selected_index].status != u8(1) {
                selected_tasks[selected_index].status = u8(1)
                changed = true
            }
        case "start":
            // Display categories
            for category, index in categories {
                fmt.println(index, category)
            }

            // Get tasks from a specific category
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_index, valid := strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_index < 0 || selected_index >= len(categories) {
                fmt.eprintln("Invalid index")
                break
            }
            selected_tasks := tasks[selected_index]

            // Display task options
            fmt.printfln("--- %s ---", categories[selected_index])
            for task, index in selected_tasks {
                if task.due_date == "" {
                    fmt.printfln("(%d) name: %s, status: %s", index, task.name, status_strings[task.status])
                } else {
                    fmt.printfln("(%d) name: %s, status: %s, due_date: %s", index, task.name, status_strings[task.status], task.due_date)
                }
            }

            // Select task to update
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_index, valid = strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_index < 0 || selected_index >= len(selected_tasks) {
                fmt.eprintln("Invalid index")
                break
            }

            // Update task
            if selected_tasks[selected_index].status != u8(2) {
                selected_tasks[selected_index].status = u8(2)
                changed = true
            }
        case "check":
            // Display categories
            for category, index in categories {
                fmt.println(index, category)
            }

            // Get tasks from a specific category
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_index, valid := strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_index < 0 || selected_index >= len(categories) {
                fmt.eprintln("Invalid index")
                break
            }
            selected_tasks := tasks[selected_index]

            // Display task options
            fmt.printfln("--- %s ---", categories[selected_index])
            for task, index in selected_tasks {
                if task.due_date == "" {
                    fmt.printfln("(%d) name: %s, status: %s", index, task.name, status_strings[task.status])
                } else {
                    fmt.printfln("(%d) name: %s, status: %s, due_date: %s", index, task.name, status_strings[task.status], task.due_date)
                }
            }

            // Select task to update
            fmt.print("Enter index: ")
            if !bufio.scanner_scan(&scanner) {
                break
            }
            selected_index, valid = strconv.parse_int(bufio.scanner_text(&scanner))
            if !valid || selected_index < 0 || selected_index >= len(selected_tasks) {
                fmt.eprintln("Invalid index")
                break
            }

            // Update task
            if selected_tasks[selected_index].status != u8(3) {
                selected_tasks[selected_index].status = u8(3)
                changed = true
            }
        case "save":
            // Write changes
            if changed {
                save_tasks(DATA_FILE, tasks, categories)
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
}
