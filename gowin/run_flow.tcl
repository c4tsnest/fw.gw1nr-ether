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
    if {[catch {open_project $project_file} err2] == 0} {
        return
    }
    puts stderr "Failed to open project '$project_file'"
    puts stderr "  open_project -file error: $err"
    puts stderr "  open_project error: $err2"
    exit 2
}

try_open_project $project_file

switch -- $step {
    synth {
        if {[catch {run syn} err] != 0} {
            puts stderr "Failed to run synthesis (run syn): $err"
            catch {close_project}
            exit 3
        }
    }
    pnr - impl - all {
        if {[catch {run pnr} err] != 0} {
            puts stderr "Failed to run PnR (run pnr): $err"
            catch {close_project}
            exit 3
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
