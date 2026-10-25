/* Glom
 *
 * Copyright (C) 2001-2004 Murray Cumming
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA.
 */

#include <glibmm/thread.h>
#include <libglom/spawn_with_feedback.h>
#include <glibmm/main.h>
#include <glibmm/spawn.h>
#include <glibmm/shell.h>
#include <glibmm/fileutils.h>
#include <glibmm/miscutils.h>
#include <stdexcept>
#include <iostream>

#ifdef G_OS_WIN32
# include <windows.h>
#endif

// Uncomment to see debug messages
//#define GLOM_SPAWN_DEBUG

namespace Glom
{

namespace Spawn
{

static void on_spawn_info_finished(const Glib::RefPtr<Glib::MainLoop>& mainloop)
{
  //Allow our mainloop.run() to return:
  if(mainloop)
    mainloop->quit();
}

// This is a simple-process launching API wrapping g_spawn_async on linux and
// CreateProcess() on Windows. We need to use CreateProcess() on Windows to be
// able to suppress the console window.
// TODO: File a bug about the console window on Windows.
namespace Impl
{

static const unsigned int REDIRECT_STDOUT = 1;
static const unsigned int REDIRECT_STDERR = 2;

class SpawnError: public std::runtime_error
{
public:
  explicit SpawnError(const std::string& error_message)
  : std::runtime_error(error_message)
  {}
};

class SpawnInfo: public sigc::trackable
{
private:
  // Private platform-dependant helper functions
#ifdef G_OS_WIN32
  static std::string win32_error_message()
  {
    gchar* message = g_win32_error_message(GetLastError());
    std::string msg = message;
    g_free(message);
    return msg;
  }
  // We redirect stdout and stderr output into a file, and read that file later.
  // I would prefer to read child stderr directly, without using a temporary
  // file, but that is probably not so easy since Glib::IOChannel does not
  // support Windows file HANDLEs, but we need to pass a HANDLE to
  // CreateProcess() for redirection.
  static HANDLE create_redirect_file(std::string& filename)
  {
    static unsigned int redirect_seq = 0;
    const auto appdata = getenv("APPDATA");
    filename = Glib::ustring::compose("%1\\glom_spawn_redirect_%2.txt", std::string(appdata), ++ redirect_seq);

    // Allow the redirect file to be inherited by the child process, so
    // it can write to it.
    SECURITY_ATTRIBUTES security_attr;
    security_attr.nLength = sizeof(security_attr);
    security_attr.lpSecurityDescriptor = nullptr;
    security_attr.bInheritHandle = true;

    HANDLE result = CreateFile(filename.c_str(), GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_DELETE, &security_attr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
    if(!result) throw SpawnError(win32_error_message());
    return result;
  }
#else // G_OS_WIN32
  bool on_io(Glib::IOCondition cond, Glib::RefPtr<Glib::IOChannel> channel, std::string& result)
  {
    if(cond != Glib::IO_IN)
    {
      // Perhaps the pipe was closed or something. Ignore & Disconnect. If the
      // this was because the child exited, then the on_child_watch() callback
      // will be called anyway.
      return false;
    }
    else
    {
      char buffer[1024 + 1];
      gsize bytes_read;

      Glib::IOStatus status = Glib::IO_STATUS_NORMAL;
      try
      {
        status = channel->read(buffer, 1024, bytes_read);
      }
      catch(const Glib::Exception& ex)
      {
        std::cerr << G_STRFUNC << ": Glom::Spawn::Impl::SpawnInfo::on_io: Error while reading from pipe: " << ex.what() << std::endl;
        return false;
      }

      buffer[bytes_read] = '\0';
      result += buffer;

      return status == Glib::IO_STATUS_NORMAL || status == Glib::IO_STATUS_AGAIN;
    }
  }

  void redirect_to_string(int fd, std::string& string)
  {
    auto channel = Glib::IOChannel::create_from_fd(fd);
    channel->set_flags(Glib::IO_FLAG_NONBLOCK);

    channel->set_encoding("");
    channel->set_buffered(false);

    Glib::signal_io().connect(sigc::bind(sigc::mem_fun(*this, &SpawnInfo::on_io), channel, std::ref(string)), channel, Glib::IO_IN);
  }
#endif // !G_OS_WIN32

public:
  using SignalFinished = sigc::signal<void ()>;

  /** TODO: Document the redirect parameter.
   */
  SpawnInfo(const Glib::ustring& command_line, int redirect, const std::vector<std::string>& envp = std::vector<std::string>()):
    running(false), return_status(0)
  {
#ifdef G_OS_WIN32
    startup_info.cb = sizeof(startup_info);
    startup_info.dwFlags = STARTF_USESTDHANDLES;
    startup_info.lpReserved = nullptr;
    startup_info.lpDesktop = nullptr;
    startup_info.lpTitle = nullptr;
    startup_info.cbReserved2 = nullptr;
    startup_info.lpReserved2 = nullptr;
    startup_info.hStdInput = INVALID_HANDLE_VALUE;

    if(redirect & REDIRECT_STDOUT)
      startup_info.hStdOutput = create_redirect_file(stdout_file);
    else
      startup_info.hStdOutput = INVALID_HANDLE_VALUE;

    if(redirect & REDIRECT_STDERR)
      startup_info.hStdError = create_redirect_file(stderr_file);
    else
      startup_info.hStdError = INVALID_HANDLE_VALUE;

    // CreateProcess needs a non-const string, so we copy command_line to provide one.
    std::vector<char> command(command_line.length() + 1);
    std::copy(command_line.data(), command_line.data() + command_line.length(), command.begin());
    command[command_line.length()] = '\0';

    if(!CreateProcess(0, &command[0], 0, 0, true, CREATE_NO_WINDOW, 0, 0, &startup_info, &process_info))
    {
      throw SpawnError(win32_error_message());
    }
#else // G_OS_WIN32
    try
    {
      std::vector<std::string> arguments = Glib::shell_parse_argv(command_line);
      int child_stdout = 0;
      int child_stderr = 0;
      if(envp.empty())
      {
        Glib::spawn_async_with_pipes(Glib::get_current_dir(), arguments, Glib::SPAWN_DO_NOT_REAP_CHILD, sigc::slot<void()>(), &pid, nullptr, (redirect & REDIRECT_STDOUT) ? &child_stdout : nullptr, (redirect & REDIRECT_STDERR) ? &child_stderr : nullptr);
      }
      else
      {
        // Give the child process its own environment instead of mutating the
        // parent's with setenv(): this code can run after GLib has created
        // worker threads, and setenv()/putenv() are not thread-safe (they
        // mutate environ), which corrupts the heap. g_spawn_async_with_pipes()
        // accepts an explicit child environment, so the parent is left alone.
        std::vector<char*> argv_c;
        argv_c.reserve(arguments.size() + 1);
        for(const auto& arg : arguments)
          argv_c.push_back(const_cast<char*>(arg.c_str()));
        argv_c.push_back(nullptr);

        std::vector<char*> envp_c;
        envp_c.reserve(envp.size() + 1);
        for(const auto& var : envp)
          envp_c.push_back(const_cast<char*>(var.c_str()));
        envp_c.push_back(nullptr);

        const std::string workdir = Glib::get_current_dir();
        GError* gerror = nullptr;
        g_spawn_async_with_pipes(workdir.c_str(), argv_c.data(), envp_c.data(),
                                 G_SPAWN_DO_NOT_REAP_CHILD, nullptr, nullptr, &pid,
                                 nullptr,
                                 (redirect & REDIRECT_STDOUT) ? &child_stdout : nullptr,
                                 (redirect & REDIRECT_STDERR) ? &child_stderr : nullptr,
                                 &gerror);
        if(gerror)
        {
          const std::string message = gerror->message ? gerror->message : "g_spawn_async_with_pipes() failed";
          g_error_free(gerror);
          throw SpawnError(message);
        }
      }
      if(redirect & REDIRECT_STDOUT)
        redirect_to_string(child_stdout, stdout_text);
      if(redirect & REDIRECT_STDERR)
        redirect_to_string(child_stderr, stderr_text);
    }
    catch(const Glib::Exception& ex)
    {
      throw SpawnError(ex.what());
    }
#endif // !G_OS_WIN32

    Glib::signal_child_watch().connect(sigc::mem_fun(*this, &SpawnInfo::on_child_watch), get_pid());
  }

  ~SpawnInfo()
  {
#ifdef G_OS_WIN32
    // TODO: Is it allowed to close the process handle while the process is still running?
    CloseHandle(process_info.hProcess);
    CloseHandle(process_info.hThread);

    if(!stdout_file.empty())
    {
      CloseHandle(startup_info.hStdOutput);
      DeleteFile(stdout_file.c_str());
    }

    if(!stderr_file.empty())
    {
      CloseHandle(startup_info.hStdError);
      DeleteFile(stderr_file.c_str());
    }
#else
    // TODO: What happens with the process if the child exits, but the mainloop
    // is not run anymore (and therefore our callback is not called) before
    // Glom exits itself? Is the child properly closed, or does it remain as
    // a zombie?
    if(running)
      Glib::signal_child_watch().connect(sigc::hide<1>(sigc::ptr_fun(Glib::spawn_close_pid)), pid);
#endif
  }

  Glib::Pid get_pid()
  {
#ifdef G_OS_WIN32
    return process_info.hProcess;
#else
    return pid;
#endif
  }

  bool is_running() const { return running; }
  int get_return_status() const { g_assert(!running); return return_status; }

  void get_stdout(std::string& out) const
  {
#ifdef G_OS_WIN32
    out = Glib::file_get_contents(stdout_file);
#else
    out = stdout_text;
#endif
  }

  void get_stderr(std::string& err) const
  {
#ifdef G_OS_WIN32
    err = Glib::file_get_contents(stderr_file);
#else
    err = stderr_text;
#endif
  }

  SignalFinished signal_finished() const { return m_signal_finished; }

private:
  void on_child_watch(Glib::Pid /* pid */, int returned)
  {
    running = false;
    return_status = returned;

    m_signal_finished.emit();
  }

  bool running;
  int return_status;
  SignalFinished m_signal_finished;

#ifdef G_OS_WIN32
  PROCESS_INFORMATION process_info;
  STARTUPINFO startup_info;
  std::string stderr_file;
  std::string stdout_file;
#else
  Glib::Pid pid;
  std::string stdout_text;
  std::string stderr_text;
#endif
};

static std::shared_ptr<const SpawnInfo> spawn_async(const Glib::ustring& command_line, int redirect, const std::vector<std::string>& envp = std::vector<std::string>())
{
  return std::shared_ptr<const SpawnInfo>(new SpawnInfo(command_line, redirect, envp));
}

/**
 * @param return_status: The return value of the command.
 * @result Whether we successfully ended the async spawn.
 */
static bool spawn_async_end(std::shared_ptr<const SpawnInfo> info, std::string* stdout_text = nullptr, std::string* stderr_text = nullptr, int* return_status = nullptr)
{
  if(stdout_text)
    info->get_stdout(*stdout_text);

  if(stderr_text)
    info->get_stderr(*stderr_text);

  if(return_status)
    *return_status = info->get_return_status();

  return !info->is_running();
}

static int spawn_sync(const Glib::ustring& command_line, std::string* stdout_text, std::string* stderr_text, const std::vector<std::string>& envp = std::vector<std::string>())
{
  int redirect_flags = 0;
  if(stdout_text)
    redirect_flags |= REDIRECT_STDOUT;

  if(stderr_text)
    redirect_flags |= REDIRECT_STDERR;

  auto mainloop = Glib::MainLoop::create(false);

  auto info = spawn_async(command_line, redirect_flags, envp); //This could throw
  info->signal_finished().connect(
    sigc::bind(sigc::ptr_fun(&on_spawn_info_finished), std::ref(mainloop) ) );

  // Block until signal_finished is emitted:
  mainloop->run();

  int return_status = 0;
  const auto returned = spawn_async_end(info, stdout_text, stderr_text, &return_status);
  g_assert(returned);
  return return_status;
}

} // namespace Impl

bool execute_command_line_and_wait(const std::string& command, const SlotProgress& slot_progress)
{
  //Show UI progress feedback while we wait for the command to finish:

  std::shared_ptr<const Impl::SpawnInfo> info;

  try
  {
    info = Impl::spawn_async(command, 0);
  }
  catch(const Impl::SpawnError& ex)
  {
    std::cerr << G_STRFUNC << ": exception: " << ex.what() << std::endl;
    return false;
  }

  auto mainloop = Glib::MainLoop::create(false);
  info->signal_finished().connect(
    sigc::bind(sigc::ptr_fun(&on_spawn_info_finished), std::ref(mainloop) ) );

  // Pulse two times a second:
  sigc::connection timeout_connection = Glib::signal_timeout().connect(
    sigc::bind_return( slot_progress, true),
    500);
  if(slot_progress)
    slot_progress(); //Make sure it is called at least once.

  //Block until signal_finished is called.
  mainloop->run();

  //Stop the timeout callback:
  timeout_connection.disconnect();

  int return_status = false;
  const auto returned = Impl::spawn_async_end(info, nullptr, nullptr, &return_status);
  if(!returned)
    return false; // User closed the dialog prematurely?

  return (return_status == EXIT_SUCCESS);
}

bool execute_command_line_and_wait(const std::string& command, const SlotProgress& slot_progress, std::string& output)
{
  //Initialize output parameter:
  output = std::string();

  //Show UI progress feedback while we wait for the command to finish:

  std::shared_ptr<const Impl::SpawnInfo> info;

  try
  {
    info = Impl::spawn_async(command, Impl::REDIRECT_STDOUT | Impl::REDIRECT_STDERR);
  }
  catch(const Impl::SpawnError& ex)
  {
    std::cerr << G_STRFUNC << ": exception: " << ex.what() << std::endl;
    return false;
  }


  auto mainloop = Glib::MainLoop::create(false);
  info->signal_finished().connect(
    sigc::bind(sigc::ptr_fun(&on_spawn_info_finished), std::ref(mainloop) ) );

  // Pulse two times a second:
  sigc::connection timeout_connection = Glib::signal_timeout().connect(
    sigc::bind_return( slot_progress, true),
    500);
  if(slot_progress)
    slot_progress(); //Make sure it is called at least once.

  //Block until signal_finished is called.
  mainloop->run();

  //Stop the timeout callback:
  timeout_connection.disconnect();

  int return_status = false;
  std::string stdout_text, stderr_text;
  const auto returned = Impl::spawn_async_end(info, &stdout_text, &stderr_text, &return_status);
  if(!returned)
    return false; // User closed the dialog prematurely?

  //std::cout << "DEBUG: command=" << command << std::endl;
  //std::cout << "  DEBUG: stdout_text=" << stdout_text << std::endl;
  //std::cout << "  DEBUG: stderr_text=" << stderr_text << std::endl;

  output = stdout_text;

  if(!stderr_text.empty())
  {
    std::cerr << G_STRFUNC << ": command produced stderr text: \n" <<
      "  command: " << command << std::endl <<
      "  error text: " << stderr_text << std::endl;
  }

  return (return_status == EXIT_SUCCESS);
}

// Callback handlers for execute_command_line_and_wait_until_second_command_returns_success
namespace
{

  bool second_command_on_timeout(const std::string& second_command, const std::string& success_text, const SlotProgress& slot_progress, const Glib::RefPtr<Glib::MainLoop>& mainloop)
  {
    std::vector<std::string> child_envp;
#ifdef G_OS_WIN32
    Glib::ustring stored_env_lang;
    Glib::ustring stored_env_language;
#endif // G_OS_WIN32
    if(!success_text.empty())
    {
      // We want a canonical (C locale) version of the command's output so we
      // can parse it. We must NOT force that with setenv()/putenv() on the
      // parent process here: this code can run after GLib has created worker
      // threads, and those functions are not thread-safe, so mutating environ
      // corrupts the heap. Instead we build a child environment with LANG and
      // LANGUAGE forced to "C" and hand it to the child process only.
#ifdef G_OS_WIN32
      // Windows is not affected by the setenv()/fork() thread-safety issue.
      stored_env_lang = Glib::getenv("LANG");
      stored_env_language = Glib::getenv("LANGUAGE");
      Glib::setenv("LANG", "C", true /* overwrite */);
      Glib::setenv("LANGUAGE", "C", true /* overwrite */);
#else
      char** env = g_get_environ();
      env = g_environ_setenv(env, "LANG", "C", TRUE);
      env = g_environ_setenv(env, "LANGUAGE", "C", TRUE);
      for(char** e = env; e && *e; ++e)
        child_envp.push_back(*e);
      g_strfreev(env);
#endif // G_OS_WIN32
    }

    #ifdef GLOM_SPAWN_DEBUG
    std::cout << std::endl << "debug: command_line (second): " << second_command << std::endl << std::endl;
    #endif //GLOM_SPAWN_DEBUG

    int return_status = 0;
    std::string stdout_output;
    try
    {
      return_status = Impl::spawn_sync(second_command, &stdout_output, nullptr, child_envp);
    }
    catch(const Impl::SpawnError& ex)
    {
      // TODO: We should cancel the whole call if this fails three times in
      std::cerr << G_STRFUNC << ": Exception while calling Glib::spawn_command_line_sync(): " << ex.what() << std::endl;
      // a row or so.
    }

#ifdef G_OS_WIN32
    if(!success_text.empty())
    {
      // Restore the previous environment variable values (Windows only; the
      // other platforms never touched the parent environment).
      Glib::setenv("LANG", stored_env_lang, true /* overwrite */);
      Glib::setenv("LANGUAGE", stored_env_language, true /* overwrite */);
    }
#endif // G_OS_WIN32

    if(return_status == EXIT_SUCCESS)
    {
      bool success = true; //Just check the return code.
      if(!success_text.empty()) //Check the output too.
      {
        #ifdef GLOM_SPAWN_DEBUG
        std::cout << " debug: output=" << stdout_output << ", waiting for=" << success_text << std::endl;
        #endif //GLOM_SPAWN_DEBUG

        if(stdout_output.find(success_text) == std::string::npos)
          success = false;
      }

      if(success)
      {
        #ifdef GLOM_SPAWN_DEBUG
        std::cout << "debug: Success, do response\n";
        #endif //GLOM_SPAWN_DEBUG

        // Exit from run() in execute_command_line_and_wait_until_second_command_returns_success().
        mainloop->quit();
        // Cancel timeout. Actually, we also could return true here since
        // the signal is disconnect explicetely after run() anyway.
        return false;
      }
    }
    else
    {
       #ifdef GLOM_SPAWN_DEBUG
       std::cout << " debug: second command failed. output=" << stdout_output << std::endl;
       #endif //GLOM_SPAWN_DEBUG
    }

    if(slot_progress)
      slot_progress(); //Show UI progress feedback.

    return true;
  }

} //Anonymous namespace

/*
static bool on_timeout_delay(const Glib::RefPtr<Glib::MainLoop>& mainloop)
{
  //Allow our mainloop.run() to return:
  if(mainloop)
    mainloop->quit();

  return false;
}
*/

bool execute_command_line_and_wait_until_second_command_returns_success(const std::string& command, const std::string& second_command, const SlotProgress& slot_progress, const std::string& success_text)
{
  #ifdef GLOM_SPAWN_DEBUG
  std::cout << "debug: Command: " << command << std::endl;
  #endif //GLOM_SPAWN_DEBUG

  std::shared_ptr<const Impl::SpawnInfo> info;

  try
  {
    info = Impl::spawn_async(command, Impl::REDIRECT_STDERR);
  }
  catch(const Impl::SpawnError& ex)
  {
    std::cerr << G_STRFUNC << ": exception: " << ex.what() << std::endl;
    return false;
  }

  // While we wait for the second command to finish we
  // a) check whether the first command finished. If it did, and has a
  // negative error code, we assume it failed and return directly.
  // b) Get stderr data, to display an error message in case the command
  // fails:

  auto mainloop = Glib::MainLoop::create(false);
  sigc::connection watch_conn = info->signal_finished().connect(
    sigc::bind(sigc::ptr_fun(&on_spawn_info_finished), std::ref(mainloop) ) );

  // Call the second command once every second
  sigc::connection timeout_conn = Glib::signal_timeout().connect(sigc::bind(sigc::ptr_fun(&second_command_on_timeout), std::ref(second_command), std::ref(success_text), slot_progress, std::ref(mainloop)), 1000);
  if(slot_progress)
    slot_progress(); //Make sure it is called at least once.

  // Block until signal_finished is emitted:
  mainloop->run();

  timeout_conn.disconnect();
  watch_conn.disconnect();

  std::string stderr_text;
  int return_status = 0;
  const auto success = Impl::spawn_async_end(info, nullptr, &stderr_text, &return_status);

  if(success && (return_status == EXIT_SUCCESS))
  {
    /* Don't sleep here. Instead we just keep trying to connect until it succeeds,
     * timing out during that if necessary.
     *
     *
    //Sleep for a bit more, because I think that pg_ctl sometimes reports success too early.
    auto mainloop = Glib::MainLoop::create(false);
    sigc::connection connection_timeout = Glib::signal_timeout().connect(
     sigc::bind(sigc::ptr_fun(&on_timeout_delay), std::ref(mainloop)),
     8000);
    mainloop->run();

    connection_timeout.disconnect();
    */

    return true;
  }
  else
  {
    // The user either cancelled, or the first command failed, or exited prematurely
    if(true) //response == Gtk::RESPONSE_REJECT)
    {
      /* TODO: Allow the caller to show a dialog?
      // Command failed
      std::shared_ptr<Gtk::MessageDialog> error_dialog;
      if(parent_window)
        error_dialog.reset(new Gtk::MessageDialog(*parent_window, "Child command failed", false, Gtk::MESSAGE_ERROR));
      else
        error_dialog.reset(new Gtk::MessageDialog("Child command failed", false, Gtk::MESSAGE_ERROR));

      // TODO: i18n
      error_dialog->set_secondary_text("The command was:\n\n" + Glib::Markup::escape_text(command) + (stderr_text.empty() ? Glib::ustring("") : ("\n\n<small>" + Glib::Markup::escape_text(stderr_text) + "</small>")), true);
      error_dialog->run();
      */
      std::cerr << G_STRFUNC << ": Child command failed. The command was: " << command << std::endl <<
        "and the error was: " << stderr_text << std::endl;
    }
    else
    {
      // User cancelled or closed pulse window
      // TODO: Terminate/Kill first command? We probably don't need
      // it any longer.
    }

    return false;
  }
}

} //Spawn

} //Glom
