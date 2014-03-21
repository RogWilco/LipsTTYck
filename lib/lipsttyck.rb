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
	@@templatePad = "\n\n"
	@@templatePrefix = ""
	@@templatePadding = " "
	@@templateIndentOn = "#@@templatePrefix#@@templatePadding"
	@@templateIndentOff = ""
	@@templateH1 = "#@@templatePrefix@gray(================================================================================)"
	@@templateH2 = "#@@templatePrefix@gray(--------------------------------------------------------------------------------)"
	@@templateDiv = "#@@templateH2"
	@@templateBlockquote = "| "
	@@templateEnd = "#@@templateH2"
	@@templateSuccess = "[  @green(OK)  ]"  # "@green(✓)", "@green(✔)"︎
	@@templateFailure = "[ @red(FAIL) ]"    # "@red(✗)", "@red(✘)"
	@@templateSkip = "[ @blue(SKIP) ]"      # "@blue(~)", "@blue(⋯)"
	@@templateColorPrompt = "@blue"
	@@templateColorStdOut = "@gray"
	@@templateColorStdErr = "@red"

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
		@entryQueued = false

		# Caches
		@cacheLast = ""
		@cacheLine = ""

		# Margin-Sensitive Template Overrides
		if(@config['marginTemplateOverrides'])
			# H1 Override
			@@templateH1 = "#@@templatePrefix@gray("

			@config['margin'].times do
				@@templateH1 += "="
			end

			@@templateH1 += ")"

			# H2 Override
			@@templateH2 = "#@@templatePrefix@gray("

			@config['margin'].times do
				@@templateH2 += "-"
			end

			@@templateH2 += ")"

			# DIV Override
			@@templateDiv = "#@@templateH2"

			# END Override
			@@templateEnd = "#@@templateH2"
		end
	end

	##
	# Outputs the specified text, processing any detected markup.
	# 
	# @param [String]  text            the text to be displayed
	# @param [Boolean] trailingNewline whether or not to automatically append a trailing newline character
	# @param [Boolean] autoIndent      whether or not to automatically apply indentation
	# @param [Boolean] rightJustified  whether or not to right-align the text according to the configured margin width
	# 
	# @return void
	# 
	def out(text, trailingNewline = true, autoIndent = true, rightJustified = false)
		formatted = "#{text}"
		unformatted = "#{text}"
		templateIndent = autoIndent ? @@templateIndentOn : @@templateIndentOff
		line = "#@cacheLine"

		# Apply Indentation
		formatted.gsub!(/\n/m, "\n#{templateIndent}")

		# Apply Markup Formatting
		case formatted
			when /@H1(?: (.*))?/im
				formatted = "#@@templateH1\n#{templateIndent}@green(#$1)\n#@@templateH1"

				# Handle Queued Entry
				if @entryQueued
					formatted = "#@@templatePad#{formatted}"
					@entryQueued = false
				end

			when /@H2(?: (.*))?/im
				stripped = $1

				if @cacheLast =~ /^@H[12](.*)/i
					formatted="#{templateIndent}@yellow(#{stripped})\n#@@templateH2"
				else
					formatted="#@@templateH2\n#{templateIndent}@yellow(#{stripped})\n#@@templateH2"
				end

				# Handle Queued Entry
				if @entryQueued
					formatted = "#@@templatePad#{formatted}"
					@entryQueued = false
				end

			when /@DIV(?: (.*))?/im
				if $1
					formatted = "#@@templateDiv\n#$1"
				else
					formatted = "#@@templateDiv"
				end

			when /@BLOCKQUOTE\((.*)(?<!\\)\)/im
				formatted = "#$1".gsub(/\n/m, "\n#@@templateBlockquote")

			when /@SUCCESS(?: (.*))?/im
				formatted = "#@@templateSuccess#@@templatePadding"

			when /@FAILURE(?: (.*))?/im
				formatted = "#@@templateFailure#@@templatePadding"

			when /@SKIP(?: (.*))?/im
				formatted = "#@@templateSkip#@@templatePadding"

			when /@ENTRY(?: (.*))?/im
				@entryQueued = true
				return

			when /@EXIT(?: (.*))?/im
				# Handle Queued Entry
				if @entryQueued
					@entryQueued = false
				else
					# Handle Exit w/ Heading
					if @cacheLast =~ /^@H[12].*/im
						# Handle Double Newline (After Heading)
						if @@templatePad[0,2] == "\n"
							formatted = @@templatePad[2,-1]
						else
							formatted = "#@@templatePad"
						end
					else
						# Handle Exit w/ Text
						if formatted.length > 5
							formatted = "#{templateIndent}" << formatted[6..-1] << "\n#@@templateEnd#@@templatePad"
						else
							formatted = "#@@templateEnd#@@templatePad"
						end
					end

					@entryQueued = false
				end
			else
				formatted = "#{templateIndent}" + formatted.gsub(/\\@/, "@")

				# Handle Queued Entry
				if @entryQueued
					formatted = "#@@templatePad#@@templateDiv\n#{formatted}"
					@entryQueued = false
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
		escapedPattern = /\\([@\(\)])/im

		stripped.gsub!(escapedPattern, "\\1")
		formatted.gsub!(escapedPattern, "\\1")

		# Apply Right-Justification
		if rightJustified
			paddingSize = (@config['margin'] - line.length) - stripped.length
			padding = "%#{paddingSize}s" % ""

			formatted = "#{padding}#{formatted}"
		end

		# Apply Trailing Newline
		if trailingNewline
			formatted = "#{formatted}\n"
		end

		# Output Formatted String
		print "#{formatted}"

		# Cache Unformatted Version
		@cacheLast = unformatted

		# Cache Current Line
		if !trailingNewline
			@cacheLine = @cacheLine << stripped
		else
			@cacheLine = ""
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

		out("#@@templateColorPrompt(#{prompt})", false)

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

		out("#@@templateColorPrompt(#{prompt})", false)

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
		commandOutputLogs = [];
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

			Open3.popen3(command) do |stdin, stdout, stderr, waitThread|
				commandOutputLogs << {
					:stdout => stdout.eof? ? nil : stdout.read,
					:stderr => stderr.eof? ? nil : stderr.read
				}

				if waitThread.value.to_i > 0
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
			lastIndex = commandOutputLogs.length - 1

			self.out("")

			commandOutputLogs.each_index do |i|
				# STDOUT
				if (@config['showStdOut'] == LOG_LEVEL_ALWAYS) || (failed && @config['showStdOut'] == LOG_LEVEL_FAILURE && i == lastIndex)
					blockquote(commandOutputLogs[i][:stdout], @@templateColorStdOut)
				end

				# STDERR
				if (@config['showStdErr']) == LOG_LEVEL_ALWAYS || (failed && @config['showStdErr'] == LOG_LEVEL_FAILURE && i == lastIndex)
					blockquote(commandOutputLogs[i][:stderr], @@templateColorStdErr)
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
