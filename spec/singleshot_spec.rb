require 'spec_helper'

describe Rack::Handler::SingleShot do
  before(:each) do
    @stdin, @in   = IO.pipe
    @out, @stdout = IO.pipe

    @app = Rack::Lint.new(lambda {|env| [200, {'Content-Type' => 'text/plain'}, []] })
    @server = Rack::Handler::SingleShot.new(@app, @stdin, @stdout)

    @server.stub(:exit)
  end

  it 'can handle a simple request' do
    @in << <<-REQUEST.gsub("\n", "\r\n")
GET / HTTP/1.1
Server-Name: localhost

REQUEST

    @server.run

    @out.read.should == <<-RESPONSE.gsub("\n", "\r\n")
HTTP/1.1 200 OK
Content-Type: text/plain

RESPONSE
  end

  describe "Sinatra App" do

    class App < Sinatra::Base
      get '/' do
        'response body'
      end

      get '/params' do
        params.inspect
      end
    end

    before(:each) do
      @stdin, @in   = IO.pipe
      @out, @stdout = IO.pipe

      @app = Rack::Lint.new(App.new)
      @server = Rack::Handler::SingleShot.new(@app, @stdin, @stdout)

      @server.stub(:exit)
    end

    it 'can handle a sinatra request' do
      @in << <<-REQUEST.gsub("\n", "\r\n")
GET / HTTP/1.1
Server-Name: localhost

REQUEST

      @server.run

      @out.read.should =~ /response body\Z/
    end

    it 'supports query string parameters' do
      @in << <<-REQUEST.gsub("\n", "\r\n")
GET /params?foo=bar&baz=bang HTTP/1.1
Server-Name: localhost

REQUEST

      @server.run

      @out.read.should include('{"foo"=>"bar", "baz"=>"bang"}')
    end
  end
end
