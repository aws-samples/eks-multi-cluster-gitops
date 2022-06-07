package version

import (
	"fmt"
	"runtime"
)

var (
	// Version variable will be replaced at link time after `make` has been run.
	Version string = "v0.1.0"
	// GitCommit variable will be replaced at link time after `make` has been run.
	GitCommit string = "<NO COMMIT HASH>"
	// BuildType variable will be replaced at link time after `make` has been run.
	BuildType string = "dev"
	Compiler  string = runtime.Compiler
	GoVersion string = "unknown"
	Platform  string = fmt.Sprintf("%s/%s", runtime.GOOS, runtime.GOARCH)
)

// Info returns a formatted string, with linebreaks, intended to be displayed
// on stdout.
func Info() string {
	return fmt.Sprintf(
		`{"Version":"%s","GitCommit":"%s","BuildType":"%s","Compiler":"%s","GoVersion":"%s","Platform":"%s"}`,
		Version,
		GitCommit,
		BuildType,
		Compiler,
		GoVersion,
		Platform,
	)
}
