module WebSocket
  class Extensions

    autoload :Parser, File.expand_path('../extensions/parser', __FILE__)

    ExtensionError = Class.new(ArgumentError)

    def initialize
      @rsv1 = @rsv2 = @rsv3 = nil

      @by_name  = {}
      @in_order = []
      @sessions = []
      @index    = {}
    end

    def add(ext)
      unless ext.respond_to?(:name) and ext.name.is_a?(String)
        raise TypeError, 'extension.name must be a string'
      end

      unless ext.respond_to?(:type) and ext.type == 'permessage'
        raise TypeError, 'extension.type must be "permessage"'
      end

      unless ext.respond_to?(:rsv1) and [true, false].include?(ext.rsv1)
        raise TypeError, 'extension.rsv1 must be true or false'
      end

      unless ext.respond_to?(:rsv2) and [true, false].include?(ext.rsv2)
        raise TypeError, 'extension.rsv2 must be true or false'
      end

      unless ext.respond_to?(:rsv3) and [true, false].include?(ext.rsv3)
        raise TypeError, 'extension.rsv3 must be true or false'
      end

      if @by_name.has_key?(ext.name)
        raise TypeError, %Q{An extension with name "#{ext.name}" is already registered}
      end

      @by_name[ext.name] = ext
      @in_order.push(ext)
    end

    def generate_offer
      sessions = []
      offer    = []
      index    = {}

      @in_order.each do |ext|
        session = ext.create_client_session
        next unless session

        sessions.push(session)
        index[ext.name] = {:ext => ext, :session => session}

        offers = session.generate_offer
        offers = offers ? [offers].flatten : []

        offers.each do |off|
          offer.push(Parser.serialize_params(ext.name, off))
        end
      end

      @sessions = sessions
      @index    = index

      offer.size > 0 ? offer.join(', ') : nil
    end

    def activate(header)
      responses = Parser.parse_header(header)
      @sessions = []

      responses.each_offer do |name, params|
        unless record = @index[name]
          raise ExtensionError, %Q{Server sent am extension response for unknown extension "#{name}"}
        end

        ext     = record[:ext]
        session = record[:session]

        if reserved = reserved?(ext)
          raise ExtensionError, %Q{Server sent two extension responses that use the RSV#{reserved[0]} } +
                               %Q{ bit: "#{reserved[1]}" and "#{ext.name}"}
        end

        unless session.activate(params) == true
          raise ExtensionError, %Q{Server send unacceptable extension parameters: #{Parser.serialize_params(name, params)}}
        end

        reserve(ext)
        @sessions.push(session)
      end
    end

    def generate_response(header)
      offers   = Parser.parse_header(header)
      sessions = []
      response = []

      @in_order.each do |ext|
        offer = offers.by_name(ext.name)
        next if offer.empty? or reserved?(ext)

        next unless session = ext.create_server_session(offer)

        reserve(ext)
        sessions.push(session)
        response.push(Parser.serialize_params(ext.name, session.generate_response))
      end

      @sessions = sessions
      response.size > 0 ? response.join(', ') : nil
    end

    def valid_frame_rsv(frame)
      allowed = {:rsv1 => false, :rsv2 => false, :rsv3 => false}

      @sessions.each do |session|
        policy = session.valid_frame_rsv(frame)
        allowed[:rsv1] ||= policy[:rsv1]
        allowed[:rsv2] ||= policy[:rsv2]
        allowed[:rsv3] ||= policy[:rsv3]
      end

      (allowed[:rsv1] || !frame.rsv1) &&
      (allowed[:rsv2] || !frame.rsv2) &&
      (allowed[:rsv3] || !frame.rsv3)
    end

    def process_incoming_message(message)
      @sessions.reverse.inject(message) do |msg, session|
        session.process_incoming_message(msg)
      end
    rescue => e
      raise ExtensionError, e.message
    end

    def process_outgoing_message(message)
      @sessions.inject(message) do |msg, session|
        session.process_outgoing_message(msg)
      end
    rescue => e
      raise ExtensionError, e.message
    end

    def close
      @sessions.each do |session|
        session.close rescue nil
      end
    end

  private

    def reserve(ext)
      @rsv1 ||= ext.rsv1 && ext.name
      @rsv2 ||= ext.rsv2 && ext.name
      @rsv3 ||= ext.rsv3 && ext.name
    end

    def reserved?(ext)
      return [1, @rsv1] if @rsv1 and ext.rsv1
      return [2, @rsv2] if @rsv2 and ext.rsv2
      return [3, @rsv3] if @rsv3 and ext.rsv3
      false
    end

  end
end
