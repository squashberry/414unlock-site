#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Single-Instance Enforcement: Prevent multiple window instances
  HANDLE hMutex = ::CreateMutex(nullptr, TRUE, L"414Unlock_Windows_SingleInstance_Mutex");
  if (hMutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Another instance is already running! Search for existing window.
    HWND hwndExisting = nullptr;
    ::EnumWindows([](HWND hwnd, LPARAM lParam) -> BOOL {
      wchar_t className[256];
      if (::GetClassName(hwnd, className, 256) && wcscmp(className, L"FLUTTER_RUNNER_WIN32_WINDOW") == 0) {
        wchar_t windowTitle[256];
        if (::GetWindowText(hwnd, windowTitle, 256) && wcsstr(windowTitle, L"414Unlock") != nullptr) {
          HWND* pFound = reinterpret_cast<HWND*>(lParam);
          *pFound = hwnd;
          return FALSE; // Found target window, stop enumeration
        }
      }
      return TRUE;
    }, reinterpret_cast<LPARAM>(&hwndExisting));

    if (!hwndExisting) {
      hwndExisting = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
    }

    if (hwndExisting) {
      // Unhide if hidden in system tray, restore if minimized, and bring to foreground
      ::ShowWindow(hwndExisting, SW_SHOW);
      ::ShowWindow(hwndExisting, SW_RESTORE);
      ::SetWindowPos(hwndExisting, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
      ::SetForegroundWindow(hwndExisting);
      ::FlashWindow(hwndExisting, TRUE);
    }
    ::CloseHandle(hMutex);
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 750);
  if (!window.Create(L"414Unlock", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
