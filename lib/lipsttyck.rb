require "open3"
require "pty"

##
# LipsTTYck provides a collection of utilities for formatting shell output. It
# parses a simple markup syntax for adding color formatting, right-justification
# of text, headers, and horizontal dividers.
# 
# @author Nick Williams
# @version 0.1.0
# 
class LipsTTYck
  # Logging/Output Levels
  LOG_LEVEL_NEVER = 0
  LOG_LEVEL_FAILURE = 1
  LOG_LEVEL_ALWAYS = 2

  # Templates
  @@template_pad = "\n\n"
  @@template_prefix = ""
  @@template_padding = " "
  @@template_indent_on = "#@@template_prefix#@@template_padding"
  @@template_indent_off = ""
  @@template_h1 = "#@@template_prefix@gray(================================================================================)"
  @@template_h2 = "#@@template_prefix@gray(--------------------------------------------------------------------------------)"
  @@template_div = "#@@template_h2"
  @@template_blockquote = "| "
  @@template_end = "#@@template_h2"
  @@template_success = "[  @green(OK)  ]"  # "@green(✓)", "@green(✔)"︎
  @@template_failure = "[ @red(FAIL) ]"    # "@red(✗)", "@red(✘)"
  @@template_skip = "[ @blue(SKIP) ]"      # "@blue(~)", "@blue(⋯)"
  @@template_color_prompt = "@blue"
  @@template_color_stdout = "@gray"
  @@template_color_stderr = "@red"

  ##
  # Initializes a new LipsTTYck instance.
  # 
  # @param [Hash] config optional configuration settings with which to initialize (overriding any defaults)
  # 
  # @return [LipsTTYck]
  # 
  def initialize(config = {})
    # Config
    @config = {
      "margin" => 80,
      "marginTemplateOverrides" => true,
      "showStdOut" => LOG_LEVEL_NEVER,
      "showStdErr" => LOG_LEVEL_FAILURE,
      "colorStdIn" => "@blue",
      "colorStdOut" => "@gray",
      "colorStdErr" => "@red"
    }

    @config.merge!(config)

    # Flags
    @entry_queued = false

    # Caches
    @cache_last = ""
    @cache_line = ""

    # Margin-Sensitive Template Overrides
    if(@config['marginTemplateOverrides'])
      # H1 Override
      @@template_h1 = "#@@template_prefix@gray("

      @config['margin'].times do
        @@template_h1 += "="
      end

      @@template_h1 += ")"

      # H2 Override
      @@template_h2 = "#@@template_prefix@gray("

      @config['margin'].times do
        @@template_h2 += "-"
      end

      @@template_h2 += ")"

      # DIV Override
      @@template_div = "#@@template_h2"

      # END Override
      @@template_end = "#@@template_h2"
    end
  end

  ##
  # Outputs the specified text, processing any detected markup.
  # 
  # @param [String]  text             the text to be displayed
  # @param [Boolean] trailing_newline whether or not to automatically append a trailing newline character
  # @param [Boolean] auto_indent      whether or not to automatically apply indentation
  # @param [Boolean] right_justified  whether or not to right-align the text according to the configured margin width
  # 
  # @return void
  # 
  def out(text, trailing_newline = true, auto_indent = true, right_justified = false)
    formatted = "#{text}"
    unformatted = "#{text}"
    template_indent = auto_indent ? @@template_indent_on : @@template_indent_off
    line = "#@cache_line"

    # Apply Indentation
    formatted.gsub!(/\n/m, "\n#{template_indent}")

    # Apply Markup Formatting
    case formatted
      when /@H1(?: (.*))?/im
        formatted = "#@@template_h1\n#{template_indent}@green(#$1)\n#@@template_h1"

        # Handle Queued Entry
        if @entry_queued
          formatted = "#@@template_pad#{formatted}"
          @entry_queued = false
        end

      when /@H2(?: (.*))?/im
        stripped = $1

        if @cache_last =~ /^@H[12](.*)/i
          formatted="#{template_indent}@yellow(#{stripped})\n#@@template_h2"
        else
          formatted="#@@template_h2\n#{template_indent}@yellow(#{stripped})\n#@@template_h2"
        end

        # Handle Queued Entry
        if @entry_queued
          formatted = "#@@template_pad#{formatted}"
          @entry_queued = false
        end

      when /@DIV(?: (.*))?/im
        if $1
          formatted = "#@@template_div\n#$1"
        else
          formatted = "#@@template_div"
        end

      when /@BLOCKQUOTE\((.*)(?<!\\)\)/im
        formatted = "#$1".gsub(/\n/m, "\n#@@template_blockquote")

      when /@SUCCESS(?: (.*))?/im
        formatted = "#@@template_success#@@template_padding"

      when /@FAILURE(?: (.*))?/im
        formatted = "#@@template_failure#@@template_padding"

      when /@SKIP(?: (.*))?/im
        formatted = "#@@template_skip#@@template_padding"

      when /@ENTRY(?: (.*))?/im
        @entry_queued = true
        return

      when /@EXIT(?: (.*))?/im
        # Handle Queued Entry
        if @entry_queued
          @entry_queued = false
        else
          # Handle Exit w/ Heading
          if @cache_last =~ /^@H[12].*/im
            # Handle Double Newline (After Heading)
            if @@template_pad[0,2] == "\n"
              formatted = @@template_pad[2,-1]
            else
              formatted = "#@@template_pad"
            end
          else
            # Handle Exit w/ Text
            if formatted.length > 5
              formatted = "#{template_indent}" << formatted[6..-1] << "\n#@@template_end#@@template_pad"
            else
              formatted = "#@@template_end#@@template_pad"
            end
          end

          @entry_queued = false
        end
      else
        formatted = "#{template_indent}" + formatted.gsub(/\\@/, "@")

        # Handle Queued Entry
        if @entry_queued
          formatted = "#@@template_pad#@@template_div\n#{formatted}"
          @entry_queued = false
        end
    end

    stripped = "#{formatted}"

    # Apply Color Formatting
    if formatted.include? "@"
      stripped = formatted.gsub(/(?<!\\)@[A-Za-z0-9\-_]*\((.*?)(?<!\\)\)/, '\1')

      formatted = formatted.gsub(/(?<!\\)@none\((.*?)\)/im, "\033[0m" << '\1' << "\033[0m")
        .gsub(/(?<!\\)@black\((.*?)(?<!\\)\)/im, "\033[0;30m" << '\1' << "\033[0m")
        .gsub(/(?<!\\)@white\((.*?)(?<!\\)\)/im, "\033[1;37m" << '\1' << "\033[0m")
        .gsub(/(?<!\\)@blue\((.*?)(?<!\\)\)/im, "\033[0;34m" << '\1' << "\033[0m")
        .gsub(/(?<!\\)@blue_lt\((.*?)(?<!\\)\)/im, "\033[1;34m" << '\1' << "\033[0m")
        .gsub(/(?<!\\)@green\((.*?)(?<!\\)\)/im, "\033[0;32m" << '\1' << "\033[0m")
        .gsub(/(?<!\\)@green_lt\((.*?)(?<!\\)\)/im, "\033[1;32m" << '\1' << "\033[0m")
        .gsub(/(?<!\\)@cyan\((.*?)(?<!\\)\)/im, "\033[0;36m" << '\1' << "\033[0m")
        .gsub(/(?<!\\)@cyan_lt\((.*?)(?<!\\)\)/im, "\033[1;36m" << '\1' << "\033[0m")
        .gsub(/(?<!\\)@red\((.*?)(?<!\\)\)/im, "\033[0;31m" << '\1' << "\033[0m")
        .gsub(/(?<!\\)@red_lt\((.*?)(?<!\\)\)/im, "\033[1;31m" << '\1' << "\033[0m")
        .gsub(/(?<!\\)@purple\((.*?)(?<!\\)\)/im, "\033[0;35m" << '\1' << "\033[0m")
        .gsub(/(?<!\\)@purple_lt\((.*?)(?<!\\)\)/im, "\033[1;35m" << '\1' << "\033[0m")
        .gsub(/(?<!\\)@yellow\((.*?)(?<!\\)\)/im, "\033[0;33m" << '\1' << "\033[0m")
        .gsub(/(?<!\\)@yellow_lt\((.*?)(?<!\\)\)/im, "\033[1;33m" << '\1' << "\033[0m")
        .gsub(/(?<!\\)@gray\((.*?)(?<!\\)\)/im, "\033[1;30m" << '\1' << "\033[0m")
        .gsub(/(?<!\\)@gray_lt\((.*?)(?<!\\)\)/im, "\033[0;37m" << '\1' << "\033[0m")
    end

    # Strip Escaping Slashes
    escaped_pattern = /\\([@\(\)])/im

    stripped.gsub!(escaped_pattern, "\\1")
    formatted.gsub!(escaped_pattern, "\\1")

    # Apply Right-Justification
    if right_justified
      padding_size = (@config['margin'] - line.length) - stripped.length
      padding = "%#{padding_size}s" % ""

      formatted = "#{padding}#{formatted}"
    end

    # Apply Trailing Newline
    if trailing_newline
      formatted = "#{formatted}\n"
    end

    # Output Formatted String
    print "#{formatted}"

    # Cache Unformatted Version
    @cache_last = unformatted

    # Cache Current Line
    if !trailing_newline
      @cache_line = @cache_line << stripped
    else
      @cache_line = ""
    end
  end

  ##
  # Prompts for input, first outputting the specified text.
  # 
  # @param [String]  label   the label to be used when prompting
  # @param [mixed]   value   the existing value if available
  # @param [mixed]   default a default fallback value if the response is blank
  # @param [Boolean] verbose whether or not to always prompt, regardless of a passed value
  # 
  # @return [mixed] the result of the prompt
  # 
  def in(label, value = nil, default = nil, verbose = false)
    # Don't continue if verbosity is off and value is already set.
    if !verbose && !self.class.unassigned(value)
      return
    end

    # Default value, falls back to existing value if possible.
    if default.nil? && !self.class.unassigned(value)
      default = value
    end

    # Prompt for input.
    prompt = "#{label}"

    if default.nil?
      prompt += ": "
    else
      prompt += " \\\(#{default}\\\): "
    end

    out("#@@template_color_prompt(#{prompt})", false)

    value = $stdin.gets.chomp

    # Fall back default value if input is empty.
    if self.class.unassigned(value)
      value = default
    end

    return value
  end

  ##
  # Prompts for a boolean response (y/n).
  # 
  # @param [String]  label   the label to be used when prompting
  # @param [Boolean] value   the existing value if available
  # @param [Boolean] default a default fallback value if the response is blank
  # @param [Boolean] verbose whether or not to always prompt, regardless of a passed value
  # 
  # @return [Boolean] the result of the confirmation prompt
  # 
  def confirm(label, value = nil, default = true, verbose = false)
    # Don't continue if verbosity is off and value is already set.
    if !verbose && !self.class.unassigned(value)
      return
    end

    # Default value, falls back to existing value if possible.
    if default.nil? && !self.class.unassigned(value)
      default = value
    end

    # Prompt for input.
    prompt = "#{label}"

    if default
      prompt += " \\\(Y/n\\\): "
    else
      prompt += " \\\(y/N\\\): "
    end

    out("#@@template_color_prompt(#{prompt})", false)

    response = $stdin.gets.chomp

    # Fall back default value if input is empty.
    if self.class.unassigned(response)
      value = default
    else
      if response.casecmp("y") == 0
        value = true
      elsif response.casecmp("n") == 0
        value = false
      else
        out "Invalid response \"#{response}\""
        value = confirm(label, value, default, verbose)
      end
    end

    return value
  end

  ##
  # Attempts to execute the specified shell command(s), capturing STDIN and
  # STDOUT for optional output to the user.
  # 
  # @param [String] label    a label to use when prompting for input
  # @param [Array]  commands one or more commands to be executed
  # 
  # @return [Boolean] whetehr or not all commands were executed successfully
  # 
  def attempt(label, commands)
    # Setup
    command_output_logs = [];
    failed = false

    # Convert single command to an array.
    if !commands.kind_of?(Array)
      commands = [commands]
    end

    # Output label.
    self.out(label, false)

    # Execute each command.
    commands.each do|command|
      # Output progress indicator for current command.
      self.out(".", false, false)

      Open3.popen3(command) do |stdin, stdout, stderr, wait_thread|
        command_output_logs << {
          :stdout => stdout.eof? ? nil : stdout.read,
          :stderr => stderr.eof? ? nil : stderr.read
        }

        if wait_thread.value.to_i > 0
          failed = true
          break
        end
      end
    end

    # Display the result of the attempted commands.
    if failed
      self.out("@FAILURE", true, false, true)
    else
      self.out("@SUCCESS", true, false, true)
    end

    # Output I/O streams according to config.
    if @config['showStdOut'] == LOG_LEVEL_ALWAYS || failed && @config['showStdOut'] == LOG_LEVEL_FAILURE || @config['showStdErr'] == LOG_LEVEL_ALWAYS || failed && @config['showStdErr'] == LOG_LEVEL_FAILURE
      last_index = command_output_logs.length - 1

      self.out("")

      command_output_logs.each_index do |i|
        # STDOUT
        if (@config['showStdOut'] == LOG_LEVEL_ALWAYS) || (failed && @config['showStdOut'] == LOG_LEVEL_FAILURE && i == last_index)
          blockquote(command_output_logs[i][:stdout], @@template_color_stdout)
        end

        # STDERR
        if (@config['showStdErr']) == LOG_LEVEL_ALWAYS || (failed && @config['showStdErr'] == LOG_LEVEL_FAILURE && i == last_index)
          blockquote(command_output_logs[i][:stderr], @@template_color_stderr)
        end
      end
    end

    return !failed
  end

  ##
  # Executes the specified command, passing any output to the respective
  # output streams.
  # 
  # @param [Array]   commands  one or more commands to be executed
  # @param [Boolean] formatted whether or not any resultin output should be formatted
  #
  # @return void
  #
  def passthru(commands, formatted = false)
    # Convert single command to an array.
    if !commands.kind_of?(Array)
      commands = [commands]
    end

    commands.each do |command|
      PTY.spawn(command) do |stdout, stdin, pid|
        stdout.each_line do |line|
          if formatted
            # self.out("#{colorStdIn}(> " + self.class.escape(command) + ")", true, false)
            self.out(@config['colorStdOut'] + "(| " + self.class.escape(line.gsub!(/\n/m, "")) + ")")
          else
            self.out(self.class.escape(line.gsub!(/\n/m, "")))
          end
        end
      end
    end
  end

  ##
  # Outputs an indented block of text.
  # 
  # @param [String] lines the text to be displayed
  # @param [String] prefix optional string to prepend to each line
  # @param [String] postfix optional string to append to each line
  # 
  # @return void
  # 
  def blockquote(lines, color = "@gray")
    if lines
      # Escape special characters.
      lines = self.class.escape(lines)

      lines.each_line do |line|
        self.out("#{color}(| " + line.gsub!(/(\n)$/, "") + ")")
      end

      self.out("")
    end
  end

  private

  ##
  # Checks if the specified variable is empty or nil.
  # 
  # @param [mixed] the value to be checked
  # 
  # @return [Boolean] whether or not the value should be considered unassigned
  # 
  def self.unassigned(var)
    result = false

    result |= ((var.respond_to? :empty?) && var.empty?)
    result |= ((var.respond_to? :nil?) && var.nil?)
    
    return result
  end

  ##
  # Escapes all special characters otherwise interpreted as formatting markup.
  # 
  # @param [String] text the text to be escaped
  # 
  # @return [String] the escaped text
  # 
  def self.escape(text)
    # Escape special characters.
    text.gsub!(/@/, "\\@")
    text.gsub!(/\(/, "\\(")
    text.gsub!(/\)/, "\\)")

    return text
  end
end
