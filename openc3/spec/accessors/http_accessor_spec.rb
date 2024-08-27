# encoding: ascii-8bit

=begin
This RSpec test program covers all the methods in the HttpAccessor class. It includes tests for:

1. Initialization with default and custom body accessors
2. Reading and writing various HTTP_ items (STATUS, PATH, METHOD, PACKET, ERROR_PACKET, QUERY_, HEADER_)
3. Delegating non-HTTP_ items to the body accessor
4. Reading and writing multiple items
5. Enforcing encoding, length, and short buffer allowance
6. Enforcing derived write conversion
=end

require 'spec_helper'
require 'openc3'
require 'openc3/accessors/http_accessor'

module OpenC3
  describe HttpAccessor do
  let(:packet) { double('packet') }
  let(:body_accessor) { double('body_accessor') }
  let(:http_accessor) { OpenC3::HttpAccessor.new(packet) }

  before do
    allow(OpenC3).to receive(:require_class).and_return(Class.new)
    allow(Class.new).to receive(:new).and_return(body_accessor)
  end

  describe '#initialize' do
    it 'initializes with default body accessor' do
      expect(OpenC3).to receive(:require_class).with('FormAccessor')
      OpenC3::HttpAccessor.new(packet)
    end

    it 'initializes with custom body accessor' do
      expect(OpenC3).to receive(:require_class).with('CustomAccessor')
      OpenC3::HttpAccessor.new(packet, 'CustomAccessor', 'arg1', 'arg2')
    end
  end

  describe '#read_item' do
    let(:item) { double('item', name: 'HTTP_STATUS') }

    context 'when packet.extra is nil' do
      before { allow(packet).to receive(:extra).and_return(nil) }

      it 'returns nil for HTTP_ items' do
        expect(http_accessor.read_item(item, nil)).to be_nil
      end
    end

    context 'when packet.extra is present' do
      before { allow(packet).to receive(:extra).and_return({'HTTP_STATUS' => 200}) }

      it 'reads HTTP_STATUS' do
        expect(http_accessor.read_item(item, nil)).to eq(200)
      end

      it 'reads HTTP_PATH' do
        allow(item).to receive(:name).and_return('HTTP_PATH')
        allow(packet).to receive(:extra).and_return({'HTTP_PATH' => '/test'})
        expect(http_accessor.read_item(item, nil)).to eq('/test')
      end

      it 'reads HTTP_METHOD' do
        allow(item).to receive(:name).and_return('HTTP_METHOD')
        allow(packet).to receive(:extra).and_return({'HTTP_METHOD' => 'GET'})
        expect(http_accessor.read_item(item, nil)).to eq('GET')
      end

      it 'reads HTTP_PACKET' do
        allow(item).to receive(:name).and_return('HTTP_PACKET')
        allow(packet).to receive(:extra).and_return({'HTTP_PACKET' => 'TEST'})
        expect(http_accessor.read_item(item, nil)).to eq('TEST')
      end

      it 'reads HTTP_ERROR_PACKET' do
        allow(item).to receive(:name).and_return('HTTP_ERROR_PACKET')
        allow(packet).to receive(:extra).and_return({'HTTP_ERROR_PACKET' => 'ERROR'})
        expect(http_accessor.read_item(item, nil)).to eq('ERROR')
      end

      it 'reads HTTP_QUERY_ items' do
        allow(item).to receive(:name).and_return('HTTP_QUERY_PARAM')
        allow(item).to receive(:key).and_return(nil)
        allow(packet).to receive(:extra).and_return({'HTTP_QUERIES' => {'PARAM' => 'value'}})
        expect(http_accessor.read_item(item, nil)).to eq('value')
      end

      it 'reads HTTP_HEADER_ items' do
        allow(item).to receive(:name).and_return('HTTP_HEADER_CONTENT_TYPE')
        allow(item).to receive(:key).and_return(nil)
        allow(packet).to receive(:extra).and_return({'HTTP_HEADERS' => {'CONTENT_TYPE' => 'application/json'}})
        expect(http_accessor.read_item(item, nil)).to eq('application/json')
      end
    end

    context 'when item is not an HTTP_ item' do
      let(:item) { double('item', name: 'BODY_ITEM') }

      it 'delegates to body_accessor' do
        expect(body_accessor).to receive(:read_item).with(item, nil)
        http_accessor.read_item(item, nil)
      end
    end
  end

  describe '#write_item' do
    let(:item) { double('item', name: 'HTTP_STATUS') }

    it 'writes HTTP_STATUS' do
      http_accessor.write_item(item, 201, nil)
      expect(packet.extra['HTTP_STATUS']).to eq(201)
    end

    it 'writes HTTP_PATH' do
      allow(item).to receive(:name).and_return('HTTP_PATH')
      http_accessor.write_item(item, '/new', nil)
      expect(packet.extra['HTTP_PATH']).to eq('/new')
    end

    it 'writes HTTP_METHOD' do
      allow(item).to receive(:name).and_return('HTTP_METHOD')
      http_accessor.write_item(item, 'POST', nil)
      expect(packet.extra['HTTP_METHOD']).to eq('post')
    end

    it 'writes HTTP_PACKET' do
      allow(item).to receive(:name).and_return('HTTP_PACKET')
      http_accessor.write_item(item, 'new_packet', nil)
      expect(packet.extra['HTTP_PACKET']).to eq('NEW_PACKET')
    end

    it 'writes HTTP_ERROR_PACKET' do
      allow(item).to receive(:name).and_return('HTTP_ERROR_PACKET')
      http_accessor.write_item(item, 'error_packet', nil)
      expect(packet.extra['HTTP_ERROR_PACKET']).to eq('ERROR_PACKET')
    end

    it 'writes HTTP_QUERY_ items' do
      allow(item).to receive(:name).and_return('HTTP_QUERY_PARAM')
      allow(item).to receive(:key).and_return(nil)
      http_accessor.write_item(item, 'new_value', nil)
      expect(packet.extra['HTTP_QUERIES']['PARAM']).to eq('new_value')
    end

    it 'writes HTTP_HEADER_ items' do
      allow(item).to receive(:name).and_return('HTTP_HEADER_CONTENT_TYPE')
      allow(item).to receive(:key).and_return(nil)
      http_accessor.write_item(item, 'application/xml', nil)
      expect(packet.extra['HTTP_HEADERS']['CONTENT_TYPE']).to eq('application/xml')
    end

    context 'when item is not an HTTP_ item' do
      let(:item) { double('item', name: 'BODY_ITEM') }

      it 'delegates to body_accessor' do
        expect(body_accessor).to receive(:write_item).with(item, 'value', nil)
        http_accessor.write_item(item, 'value', nil)
      end
    end
  end

  describe '#read_items' do
    let(:http_item) { double('http_item', name: 'HTTP_STATUS') }
    let(:body_item) { double('body_item', name: 'BODY_ITEM') }

    it 'reads both HTTP and body items' do
      allow(packet).to receive(:extra).and_return({'HTTP_STATUS' => 200})
      expect(body_accessor).to receive(:read_items).with([body_item], nil).and_return({'BODY_ITEM' => 'value'})
      result = http_accessor.read_items([http_item, body_item], nil)
      expect(result).to eq({'HTTP_STATUS' => 200, 'BODY_ITEM' => 'value'})
    end
  end

  describe '#write_items' do
    let(:http_item) { double('http_item', name: 'HTTP_STATUS') }
    let(:body_item) { double('body_item', name: 'BODY_ITEM') }

    it 'writes both HTTP and body items' do
      expect(body_accessor).to receive(:write_items).with([body_item], [200, 'value'], nil)
      http_accessor.write_items([http_item, body_item], [200, 'value'], nil)
      expect(packet.extra['HTTP_STATUS']).to eq(200)
    end
  end

  describe '#enforce_encoding' do
    it 'delegates to body_accessor' do
      expect(body_accessor).to receive(:enforce_encoding)
      http_accessor.enforce_encoding
    end
  end

  describe '#enforce_length' do
    it 'delegates to body_accessor' do
      expect(body_accessor).to receive(:enforce_length)
      http_accessor.enforce_length
    end
  end

  describe '#enforce_short_buffer_allowed' do
    it 'delegates to body_accessor' do
      expect(body_accessor).to receive(:enforce_short_buffer_allowed)
      http_accessor.enforce_short_buffer_allowed
    end
  end

  describe '#enforce_derived_write_conversion' do
    context 'with HTTP_ items' do
      it 'returns false for HTTP_ items' do
        item = double('item', name: 'HTTP_STATUS')
        expect(http_accessor.enforce_derived_write_conversion(item)).to be false
      end
    end

    context 'with non-HTTP_ items' do
      it 'delegates to body_accessor for non-HTTP_ items' do
        item = double('item', name: 'BODY_ITEM')
        expect(body_accessor).to receive(:enforce_derived_write_conversion).with(item)
        http_accessor.enforce_derived_write_conversion(item)
      end
    end
  end
end
