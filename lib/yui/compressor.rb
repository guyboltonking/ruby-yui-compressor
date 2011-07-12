require "shellwords"
require "stringio"
require "tempfile"

module YUI #:nodoc:
  class Compressor
    VERSION = "0.9.6"

    class Error < StandardError; end
    class OptionError   < Error; end
    class RuntimeError  < Error; end

    attr_reader :options

    def self.default_options #:nodoc:
      { :charset => "utf-8", :line_break => nil }
    end

    def self.compressor_type #:nodoc:
      raise Error, "create a CssCompressor or JavaScriptCompressor instead"
    end

    def initialize(options = {}) #:nodoc:
      @options = self.class.default_options.merge(options)
      java_opts = @options.delete(:java_opts)
      @command = [path_to_java]
      @command << java_opts if java_opts
      @command += ["-jar", path_to_jar_file, *(command_option_for_type + command_options)]
    end

    def command #:nodoc:
      @command.map { |word| Shellwords.escape(word) }.join(" ")
    end

    # Compress a stream or string of code with YUI Compressor. (A stream is
    # any object that responds to +read+ and +close+ like an IO.) If a block
    # is given, you can read the compressed code from the block's argument.
    # Otherwise, +compress+ returns a string of compressed code.
    #
    # ==== Example: Compress CSS
    #   compressor = YUI::CssCompressor.new
    #   compressor.compress(<<-END_CSS)
    #     div.error {
    #       color: red;
    #     }
    #     div.warning {
    #       display: none;
    #     }
    #   END_CSS
    #   # => "div.error{color:red;}div.warning{display:none;}"
    #
    # ==== Example: Compress JavaScript
    #   compressor = YUI::JavaScriptCompressor.new
    #   compressor.compress('(function () { var foo = {}; foo["bar"] = "baz"; })()')
    #   # => "(function(){var foo={};foo.bar=\"baz\"})();"
    #
    # ==== Example: Compress and gzip a file on disk
    #   File.open("my.js", "r") do |source|
    #     Zlib::GzipWriter.open("my.js.gz", "w") do |gzip|
    #       compressor.compress(source) do |compressed|
    #         while buffer = compressed.read(4096)
    #           gzip.write(buffer)
    #         end
    #       end
    #     end
    #   end
    #
    def compress(stream_or_string)
      streamify(stream_or_string) do |stream|
        tempfile = Tempfile.new('yui_compress')
        tempfile.set_encoding 'binary'
        tempfile.write stream.read
        tempfile.flush

        begin
          output = `#{command} #{tempfile.path}`
          # Under JRuby 1.6.2 in 1.9 mode, Kernel.` always returns an
          # unencoded string, whereas MRI 1.9 respects
          # Encoding.default_internal/default_external, and returns a
          # string encoded with default_internal, so...
          if Encoding.default_internal == Encoding.default_external
            # ...this will have no effect on MRI, as the string encoding will
            # _already_ be default_internal, but on JRuby, it will force the
            # result to be the same as MRI.
            output = output.force_encoding(Encoding.default_internal)
          end
        rescue Exception
          raise RuntimeError, "compression failed"
        ensure
          tempfile.close!
        end

        if $?.exitstatus.zero?
          output
        else
          raise RuntimeError, "compression failed"
        end
      end
    end

    private
      def command_options
        options.inject([]) do |command_options, (name, argument)|
          method = begin
            method(:"command_option_for_#{name}")
          rescue NameError
            raise OptionError, "undefined option #{name.inspect}"
          end

          command_options.concat(method.call(argument))
        end
      end

      def path_to_java
        options.delete(:java) || "java"
      end

      def path_to_jar_file
        options.delete(:jar_file) || File.join(File.dirname(__FILE__), *%w".. yuicompressor-2.4.4.jar")
      end

      def streamify(stream_or_string)
        if stream_or_string.respond_to?(:read)
          yield stream_or_string
        else
          yield StringIO.new(stream_or_string.to_s)
        end
      end

      def command_option_for_type
        ["--type", self.class.compressor_type.to_s]
      end

      def command_option_for_charset(charset)
        ["--charset", charset.to_s]
      end

      def command_option_for_line_break(line_break)
        line_break ? ["--line-break", line_break.to_s] : []
      end
  end

  class CssCompressor < Compressor
    def self.compressor_type #:nodoc:
      "css"
    end

    # Creates a new YUI::CssCompressor for minifying CSS code.
    #
    # Options are:
    #
    # <tt>:charset</tt>::    Specifies the character encoding to use. Defaults to
    #                        <tt>"utf-8"</tt>.
    # <tt>:line_break</tt>:: By default, CSS will be compressed onto a single
    #                        line. Use this option to specify the maximum
    #                        number of characters in each line before a newline
    #                        is added. If <tt>:line_break</tt> is 0, a newline
    #                        is added after each CSS rule.
    #
    def initialize(options = {})
      super
    end
  end

  class JavaScriptCompressor < Compressor
    def self.compressor_type #:nodoc:
      "js"
    end

    def self.default_options #:nodoc:
      super.merge(
        :munge    => false,
        :optimize => true,
        :preserve_semicolons => false
      )
    end

    # Creates a new YUI::JavaScriptCompressor for minifying JavaScript code.
    #
    # Options are:
    #
    # <tt>:charset</tt>::    Specifies the character encoding to use. Defaults to
    #                        <tt>"utf-8"</tt>.
    # <tt>:line_break</tt>:: By default, JavaScript will be compressed onto a
    #                        single line. Use this option to specify the
    #                        maximum number of characters in each line before a
    #                        newline is added. If <tt>:line_break</tt> is 0, a
    #                        newline is added after each JavaScript statement.
    # <tt>:munge</tt>::      Specifies whether YUI Compressor should shorten local
    #                        variable names when possible. Defaults to +false+.
    # <tt>:optimize</tt>::   Specifies whether YUI Compressor should optimize
    #                        JavaScript object property access and object literal
    #                        declarations to use as few characters as possible.
    #                        Defaults to +true+.
    # <tt>:preserve_semicolons</tt>:: Defaults to +false+. If +true+, YUI
    #                                 Compressor will ensure semicolons exist
    #                                 after each statement to appease tools like
    #                                 JSLint.
    #
    def initialize(options = {})
      super
    end

    private
      def command_option_for_munge(munge)
        munge ? [] : ["--nomunge"]
      end

      def command_option_for_optimize(optimize)
        optimize ? [] : ["--disable-optimizations"]
      end

      def command_option_for_preserve_semicolons(preserve_semicolons)
        preserve_semicolons ? ["--preserve-semi"] : []
      end
  end
end
