require "spec_helper"

describe WebSocket::Extensions::Parser do
  describe :parse_header do
    def parse(string)
      WebSocket::Extensions::Parser.parse_header(string).to_a
    end

    it "parses an empty header" do
      expect(parse '').to eq []
    end

    it "parses a missing header" do
      expect(parse nil).to eq []
    end

    it "raises on invalid input" do
      expect { parse 'a,' }.to raise_error(WebSocket::Extensions::Parser::ParseError)
    end

    it "parses one offer with no params" do
      expect(parse 'a').to eq [
        { :name => "a", :params => {} }
      ]
    end

    it "parses two offers with no params" do
      expect(parse 'a, b').to eq [
        { :name => "a", :params => {} }, { :name => "b", :params => {} }
      ]
    end

    it "parses a duplicate offer name" do
      expect(parse 'a, a').to eq [
        { :name => "a", :params => {} },
        { :name => "a", :params => {} }
      ]
    end

    it "parses a flag" do
      expect(parse 'a; b').to eq [
        { :name => "a", :params => { "b" => true } }
      ]
    end

    it "parses an unquoted param" do
      expect(parse 'a; b=1').to eq [
        { :name => "a", :params => { "b" => 1 } }
      ]
    end

    it "parses a quoted param" do
      expect(parse 'a; b="hi, \"there"').to eq [
        { :name => "a", :params => { "b" => 'hi, "there' } }
      ]
    end

    it "parses multiple params" do
      expect(parse 'a; b; c=1; d="hi"').to eq [
        { :name => "a", :params => { "b" => true, "c" => 1, "d" => "hi" } }
      ]
    end

    it "parses duplicate params" do
      expect(parse 'a; b; c=1; b="hi"').to eq [
        { :name => "a", :params => { "b" => [true, "hi"], "c" => 1 } }
      ]
    end

    it "parses multiple complex offers" do
      expect(parse 'a; b=1, c, b; d, c; e="hi, there"; e, a; b').to eq [
        { :name => "a", :params => { "b" => 1 } },
        { :name => "c", :params => {} },
        { :name => "b", :params => { "d" => true } },
        { :name => "c", :params => { "e" => ['hi, there', true] } },
        { :name => "a", :params => { "b" => true } }
      ]
    end

    it "rejects a string missing its closing quote" do
      expect {
        parse "foo; bar=\"fooa\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a\\a"
      }.to raise_error(WebSocket::Extensions::Parser::ParseError)
    end
  end

  describe :serialize_params do
    def serialize(name, params)
      WebSocket::Extensions::Parser.serialize_params(name, params)
    end

    it "serializes empty params" do
      expect(serialize "a", {}).to eq 'a'
    end

    it "serializes a flag" do
      expect(serialize "a", "b" => true).to eq 'a; b'
    end

    it "serializes an unquoted param" do
      expect(serialize "a", "b" => 42).to eq 'a; b=42'
    end

    it "serializes a quoted param" do
      expect(serialize "a", "b" => "hi, there").to eq 'a; b="hi, there"'
    end

    it "serializes multiple params" do
      expect(serialize "a", "b" => true, "c" => 1, "d" => "hi").to eq 'a; b; c=1; d=hi'
    end

    it "serializes duplicate params" do
      expect(serialize "a", "b" => [true, "hi"], "c" => 1).to eq 'a; b; b=hi; c=1'
    end
  end
end
