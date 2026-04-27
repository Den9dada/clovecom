#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// Creates a console for the process, and redirects stdout and stderr to
// it for both the runner and the Flutter library.
void CreateAndAttachConsole();

// Appends a startup trace entry to the diagnostic log in %TEMP%.
void LogStartupEvent(const wchar_t* message);

// Takes a null-terminated wchar_t* encoded in UTF-16 and returns a std::string
// encoded in UTF-8. Returns an empty std::string on failure.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Sets the current working directory to the directory containing this
// executable. This keeps relative Flutter asset paths stable when launched from
// a shortcut, another working directory, or a packed Enigma executable.
void SetCurrentDirectoryToExecutablePath();

// Verifies Flutter runtime files are visible before engine startup. Shows a
// message box and writes a diagnostic log if the packaged executable cannot see
// its required runtime files.
bool ValidateFlutterRuntimeFiles();

// Gets the command line arguments passed in as a std::vector<std::string>,
// encoded in UTF-8. Returns an empty std::vector<std::string> on failure.
std::vector<std::string> GetCommandLineArguments();

#endif  // RUNNER_UTILS_H_
