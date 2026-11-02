require 'strscan'

module WebSocket
  class Extensions

    # RFC 6455 grammar rules:
    #
    #       Sec-WebSocket-Extensions = extension-list
    #
    #       extension-list    = 1#extension
    #
    #       extension         = extension-token *( ";" extension-param )
    #
    #       extension-token   = registered-token
    #
    #       registered-token  = token
    #
    #       extension-param   = token [ "=" (token | quoted-string) ]
    #            ; When using the quoted-string syntax variant, the value
    #            ; after quoted-string unescaping MUST conform to the
    #            ; 'token' ABNF.
    #
    # These make use of the following rules from RFC 2616:
    #
    #       token          = 1*<any CHAR except CTLs or separators>
    #
    #       separators     = "(" | ")" | "<" | ">" | "@"
    #                      | "," | ";" | ":" | "\" | <">
    #                      | "/" | "[" | "]" | "?" | "="
    #                      | "{" | "}" | SP | HT
    #
    #       quoted-string  = ( <"> *(qdtext | quoted-pair ) <"> )
    #
    #       qdtext         = <any TEXT except <">>
    #
    #       quoted-pair    = "\" CHAR
    #
    #       CHAR           = <any US-ASCII character (octets 0 - 127)>
    #
    #       CTL            = <any US-ASCII control character
    #                        (octets 0 - 31) and DEL (127)>
    #
    #       TEXT           = <any OCTET except CTLs, but including LWS>
    #
    #       LWS            = [CRLF] 1*( SP | HT )
    #
    #       SP             = <US-ASCII SP, space (32)>
    #
    #       HT             = <US-ASCII HT, horizontal-tab (9)>

    class Parser
      TOKEN    = /([!#\$%&'\*\+\-\.\^_`\|~0-9A-Za-z]+)/
      NOTOKEN  = /([^!#\$%&'\*\+\-\.\^_`\|~0-9A-Za-z])/
      QUOTED   = /"((?:\\[\x00-\x7f]|[^\x00-\x08\x0a-\x1f\x7f"\\])*)"/
      NUMBER   = /\A-?(0|[1-9][0-9]*)(\.[0-9]+)?\z/

      LWS      = /[ \t]*(?:\r\n[ \t]+)*/
      EQL      = %r{#{ LWS.source }=#{ LWS.source }}
      SEM      = %r{#{ LWS.source };#{ LWS.source }}
      COM      = %r{#{ LWS.source },#{ LWS.source }}

      PARAM    = %r{#{ TOKEN.source }(?:#{ EQL.source }(?:#{ TOKEN.source }|#{ QUOTED.source }))?}
      EXT      = %r{#{ TOKEN.source }(?:#{ SEM.source }#{ PARAM.source })*}
      EXT_LIST = %r{\A#{ EXT.source }(?:#{ COM.source }#{ EXT.source })*\z}

      ParseError = Class.new(ArgumentError)

      def self.parse_header(header)
        offers = Offers.new
        return offers if header == '' or header.nil?

        unless header =~ EXT_LIST
          raise ParseError, "Invalid Sec-WebSocket-Extensions header: #{ header }"
        end

        scanner = StringScanner.new(header)
        value   = scanner.scan(EXT)

        until value.nil?
          params = value.scan(PARAM)
          name   = params.shift.first
          offer  = {}

          params.each do |key, unquoted, quoted|
            if unquoted
              data = unquoted
            elsif quoted
              data = quoted.gsub(/\\/, '')
            else
              data = true
            end
            if data != true and data =~ NUMBER
              data = data =~ /\./ ? data.to_f : data.to_i(10)
            end

            if offer.has_key?(key)
              offer[key] = [*offer[key]] + [data]
            else
              offer[key] = data
            end
          end

          offers.push(name, offer)

          scanner.scan(COM)
          value = scanner.scan(EXT)
        end

        offers
      end

      def self.serialize_params(name, params)
        values = []

        print = lambda do |key, value|
          case value
          when Array   then value.each { |v| print[key, v] }
          when true    then values.push(key)
          when Numeric then values.push(key + '=' + value.to_s)
          else
            if value =~ NOTOKEN
              values.push(key + '="' + value.gsub(/"/, '\"') + '"')
            else
              values.push(key + '=' + value)
            end
          end
        end

        params.keys.sort.each { |key| print[key, params[key]] }

        ([name] + values).join('; ')
      end
    end

    class Offers
      def initialize
        @by_name  = {}
        @in_order = []
      end

      def push(name, params)
        @by_name[name] ||= []
        @by_name[name].push(params)
        @in_order.push(:name => name, :params => params)
      end

      def each_offer(&block)
        @in_order.each do |offer|
          block.call(offer[:name], offer[:params])
        end
      end

      def by_name(name)
        @by_name[name] || []
      end

      def to_a
        @in_order.dup
      end
    end

  end
end
