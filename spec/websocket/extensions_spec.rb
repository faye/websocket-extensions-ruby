require "spec_helper"

describe WebSocket::Extensions do
  ExtensionError = WebSocket::Extensions::ExtensionError
  Message = Struct.new(:frames)

  before do
    @extensions = WebSocket::Extensions.new

    @ext     = double(:extension, :name => "deflate", :type => "permessage", :rsv1 => true, :rsv2 => false, :rsv3 => false)
    @session = double(:session)
  end

  describe :add do
    it "does not raise on valid extensions" do
      expect { @extensions.add(@ext) }.not_to raise_error
    end

    it "raises if ext.name is not a string" do
      allow(@ext).to receive(:name).and_return(42)
      expect { @extensions.add(@ext) }.to raise_error(TypeError)
    end

    it "raises if ext.rsv1 is not a boolean" do
      allow(@ext).to receive(:rsv1).and_return(42)
      expect { @extensions.add(@ext) }.to raise_error(TypeError)
    end

    it "raises if ext.rsv2 is not a boolean" do
      allow(@ext).to receive(:rsv2).and_return(42)
      expect { @extensions.add(@ext) }.to raise_error(TypeError)
    end

    it "raises if ext.rsv3 is not a boolean" do
      allow(@ext).to receive(:rsv3).and_return(42)
      expect { @extensions.add(@ext) }.to raise_error(TypeError)
    end
  end

  describe "client sessions" do
    before do
      @offer = {"mode" => "compress"}
      allow(@ext).to receive(:create_client_session).and_return(@session)
      allow(@session).to receive(:generate_offer).and_return(@offer)
      @extensions.add(@ext)

      @conflict = double(:extension, :name => "tar", :type => "permessage", :rsv1 => true, :rsv2 => false, :rsv3 => false)
      @conflict_session = double(:session)
      allow(@conflict).to receive(:create_client_session).and_return(@conflict_session)
      allow(@conflict_session).to receive(:generate_offer).and_return("gzip" => true)

      @nonconflict = double(:extension, :name => "reverse", :type => "permessage", :rsv1 => false, :rsv2 => true, :rsv3 => false)
      @nonconflict_session = double(:session)
      allow(@nonconflict).to receive(:create_client_session).and_return(@nonconflict_session)
      allow(@nonconflict_session).to receive(:generate_offer).and_return("utf8" => true)

      allow(@session).to receive(:activate).and_return(true)
      allow(@conflict_session).to receive(:activate).and_return(true)
      allow(@nonconflict_session).to receive(:activate).and_return(true)
    end

    describe :generate_offer do
      it "asks the extension to create a client session" do
        expect(@ext).to receive(:create_client_session).exactly(1).and_return(@session)
        @extensions.generate_offer
      end

      it "asks the session to generate an offer" do
        expect(@session).to receive(:generate_offer).exactly(1).and_return(@offer)
        @extensions.generate_offer
      end

      it "does not ask the session to generate an offer if the extension doesn't build a session" do
        allow(@ext).to receive(:create_client_session).and_return(nil)
        expect(@session).not_to receive(:generate_offer)
        @extensions.generate_offer
      end

      it "returns the serialized offer from the session" do
        expect(@extensions.generate_offer).to eq "deflate; mode=compress"
      end

      it "returns a null offer from the session" do
        allow(@session).to receive(:generate_offer).and_return(nil)
        expect(@extensions.generate_offer).to be_nil
      end

      it "returns multiple serialized offers from the session" do
        allow(@session).to receive(:generate_offer).and_return([@offer, {}])
        expect(@extensions.generate_offer).to eq "deflate; mode=compress, deflate"
      end

      it "returns serialized offers from multiple sessions" do
        @extensions.add(@nonconflict)
        expect(@extensions.generate_offer).to eq "deflate; mode=compress, reverse; utf8"
      end

      it "generates offers for potentially conflicting extensions" do
        @extensions.add(@conflict)
        expect(@extensions.generate_offer).to eq "deflate; mode=compress, tar; gzip"
      end
    end

    describe :activate do
      before do
        @extensions.add(@conflict)
        @extensions.add(@nonconflict)
        @extensions.generate_offer
      end

      it "raises if given unregistered extensions" do
        expect { @extensions.activate("xml") }.to raise_error(ExtensionError)
      end

      it "does not raise if given registered extensions" do
        expect { @extensions.activate("deflate") }.not_to raise_error
      end

      it "does not raise if given only one potentially conflicting extension" do
        expect { @extensions.activate("tar") }.not_to raise_error
      end

      it "raises if two extensions conflict on RSV bits" do
        expect { @extensions.activate("deflate, tar") }.to raise_error(ExtensionError)
      end

      it "does not raise if given two non-conflicting extensions" do
        expect { @extensions.activate("deflate, reverse") }.not_to raise_error
      end

      it "activates one session with no params" do
        expect(@session).to receive(:activate).with({}).exactly(1).and_return(true)
        @extensions.activate("deflate")
      end

      it "activates one session with a boolean param" do
        expect(@session).to receive(:activate).with("gzip" => true).exactly(1).and_return(true)
        @extensions.activate("deflate; gzip")
      end

      it "activates one session with a string param" do
        expect(@session).to receive(:activate).with("mode" => "compress").exactly(1).and_return(true)
        @extensions.activate("deflate; mode=compress")
      end

      it "activate multiple sessions" do
        expect(@session).to receive(:activate).with("a" => true).exactly(1).and_return(true)
        expect(@nonconflict_session).to receive(:activate).with("b" => true).exactly(1).and_return(true)
        @extensions.activate("deflate; a, reverse; b")
      end

      it "does not activate extensions not named in the header" do
        expect(@session).not_to receive(:activate)
        expect(@nonconflict_session).to receive(:activate).exactly(1).and_return(true)
        @extensions.activate("reverse")
      end

      it "raises if session.activate does not return true" do
        allow(@session).to receive(:activate).and_return("yes")
        expect { @extensions.activate("deflate") }.to raise_error(ExtensionError)
      end
    end

    describe :process_incoming_message do
      before do
        @extensions.add(@conflict)
        @extensions.add(@nonconflict)
        @extensions.generate_offer

        allow(@session).to receive(:process_incoming_message) do |message|
          message.frames << "deflate"
          message
        end

        allow(@nonconflict_session).to receive(:process_incoming_message) do |message|
          message.frames << "reverse"
          message
        end
      end

      it "processes messages in the reverse order given in the server's response" do
        @extensions.activate("deflate, reverse")
        message = @extensions.process_incoming_message(Message.new [])
        expect(message.frames).to eq ["reverse", "deflate"]
      end

      it "raises if a session yields an error" do
        @extensions.activate("deflate")
        allow(@session).to receive(:process_incoming_message).and_raise(TypeError)
        expect { @extensions.process_incoming_message(Message.new []) }.to raise_error(ExtensionError)
      end

      it "does not call sessions after one has yield an error" do
        @extensions.activate("deflate, reverse")
        allow(@nonconflict_session).to receive(:process_incoming_message).and_raise(TypeError)

        expect(@session).not_to receive(:process_incoming_message)

        @extensions.process_incoming_message(Message.new []) rescue nil
      end
    end

    describe :process_outgoing_message do
      before do
        @extensions.add(@conflict)
        @extensions.add(@nonconflict)
        @extensions.generate_offer

        allow(@session).to receive(:process_outgoing_message) do |message|
          message.frames << "deflate"
          message
        end

        allow(@nonconflict_session).to receive(:process_outgoing_message) do |message|
          message.frames << "reverse"
          message
        end
      end

      it "processes messages in the order given in the server's response" do
        @extensions.activate("deflate, reverse")
        message = @extensions.process_outgoing_message(Message.new [])
        expect(message.frames).to eq ["deflate", "reverse"]
      end

      it "processes messages in the server's order, not the client's order" do
        @extensions.activate("reverse, deflate")
        message = @extensions.process_outgoing_message(Message.new [])
        expect(message.frames).to eq ["reverse" ,"deflate"]
      end

      it "raises if a session yields an error" do
        @extensions.activate("deflate")
        allow(@session).to receive(:process_outgoing_message).and_raise(TypeError)
        expect { @extensions.process_outgoing_message(Message.new []) }.to raise_error(ExtensionError)
      end

      it "does not call sessions after one has yield an error" do
        @extensions.activate("deflate, reverse")
        allow(@session).to receive(:process_outgoing_message).and_raise(TypeError)

        expect(@nonconflict_session).not_to receive(:process_outgoing_message)

        @extensions.process_outgoing_message(Message.new []) rescue nil
      end
    end
  end

  describe "server sessions" do
    before do
      @response = {"mode" => "compress"}
      allow(@ext).to receive(:create_server_session).and_return(@session)
      allow(@session).to receive(:generate_response).and_return(@response)

      @conflict = double(:extension, :name => "tar", :type => "permessage", :rsv1 => true, :rsv2 => false, :rsv3 => false)
      @conflict_session = double(:session)
      allow(@conflict).to receive(:create_server_session).and_return(@conflict_session)
      allow(@conflict_session).to receive(:generate_response).and_return("gzip" => true)

      @nonconflict = double(:extension, :name => "reverse", :type => "permessage", :rsv1 => false, :rsv2 => true, :rsv3 => false)
      @nonconflict_session = double(:session)
      allow(@nonconflict).to receive(:create_server_session).and_return(@nonconflict_session)
      allow(@nonconflict_session).to receive(:generate_response).and_return("utf8" => true)

      @extensions.add(@ext)
      @extensions.add(@conflict)
      @extensions.add(@nonconflict)
    end

    describe :generate_response do
      it "asks the extension for a server session with the offer" do
        expect(@ext).to receive(:create_server_session).with([{"flag" => true}]).exactly(1).and_return(@session)
        @extensions.generate_response("deflate; flag")
      end

      it "asks the extension for a server session with multiple offers" do
        expect(@ext).to receive(:create_server_session).with([{"a" => true}, {"b" => true}]).exactly(1).and_return(@session)
        @extensions.generate_response("deflate; a, deflate; b")
      end

      it "asks the session to generate a response" do
        expect(@session).to receive(:generate_response).exactly(1).and_return(@response)
        @extensions.generate_response("deflate")
      end

      it "asks multiple sessions to generate a response" do
        expect(@session).to receive(:generate_response).exactly(1).and_return(@response)
        expect(@nonconflict_session).to receive(:generate_response).exactly(1).and_return(@response)
        @extensions.generate_response("deflate, reverse")
      end

      it "does not ask the session to generate a response if the extension doesn't build a session" do
        allow(@ext).to receive(:create_server_session).and_return(nil)
        expect(@session).not_to receive(:generate_response)
        @extensions.generate_response("deflate")
      end

      it "does not ask the extension to build a session for unoffered extensions" do
        expect(@nonconflict).not_to receive(:create_server_session)
        @extensions.generate_response("deflate")
      end

      it "does not ask the extension to build a session for conflicting extensions" do
        expect(@conflict).not_to receive(:create_server_session)
        @extensions.generate_response("deflate, tar")
      end

      it "returns the serialized response from the session" do
        expect(@extensions.generate_response("deflate")).to eq "deflate; mode=compress"
      end

      it "returns serialized responses from multiple sessions" do
        expect(@extensions.generate_response("deflate, reverse")).to eq "deflate; mode=compress, reverse; utf8"
      end

      it "returns responses in registration orde" do
        expect(@extensions.generate_response("reverse, deflate")).to eq "deflate; mode=compress, reverse; utf8"
      end

      it "does not return responses for unoffered extensions" do
        expect(@extensions.generate_response("reverse")).to eq "reverse; utf8"
      end

      it "does not return responses for conflicting extensions" do
        expect(@extensions.generate_response("deflate, tar")).to eq "deflate; mode=compress"
      end

      it "returns a response for potentially conflicting extensions if their preceeding extensions don't build a session" do
        allow(@ext).to receive(:create_server_session).and_return(nil)
        expect(@extensions.generate_response("deflate, tar")).to eq "tar; gzip"
      end

    end
  end
end
