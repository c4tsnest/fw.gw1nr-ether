if {[llength $argv] < 1} {
    puts stderr "Usage: run_flow.tcl <project.gprj> [synth|pnr]"
    exit 1
}

set project_file [lindex $argv 0]
set step "pnr"
if {[llength $argv] >= 2} {
    set step [string tolower [lindex $argv 1]]
}

proc try_open_project {project_file} {
    if {[catch {open_project -file $project_file} err] == 0} {
        return
    }
    if {[catch {open_project $project_file} err2] == 0} {
        return
    }
    puts stderr "Failed to open project '$project_file'"
    puts stderr "  open_project -file error: $err"
    puts stderr "  open_project error: $err2"
    exit 2
}

proc try_run_candidates {candidates} {
    foreach candidate $candidates {
        if {[catch {eval $candidate} err] == 0} {
            puts "Executed: $candidate"
            return
        }
        puts "Attempt failed: $candidate ($err)"
    }
    puts stderr "No compatible run command worked in this gw_sh environment"
    exit 3
}

try_open_project $project_file

switch -- $step {
    synth {
        try_run_candidates {
            {run Synthesis}
            {run synthesis}
            {run syn}
            {run all}
        }
    }
    pnr - impl - all {
        try_run_candidates {
            {run Pnr}
            {run pnr}
            {run all}
        }
    }
    default {
        puts stderr "Unknown step '$step'. Use synth or pnr"
        catch {close_project}
        exit 4
    }
}

catch {close_project}
exit 0
