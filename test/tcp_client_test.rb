# Allow test to be run in-place without requiring a gem install
$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'resilient_socket'
require 'test/simple_tcp_server'

SemanticLogger::Logger.default_level = :trace
SemanticLogger::Logger.appenders << SemanticLogger::Appender::File.new('test.log')

# Unit Test for ResilientSocket::TCPClient
class TCPClientTest < Test::Unit::TestCase
  context ResilientSocket::TCPClient do

    context "without server" do
      should "raise exception when cannot reach server after 5 retries" do
        exception = assert_raise ResilientSocket::ConnectionFailure do
          ResilientSocket::TCPClient.new(
            :server                 => 'localhost:3300',
            :connect_retry_interval => 0.1,
            :connect_retry_count    => 5)
        end
        assert_match /After 5 attempts: Errno::ECONNREFUSED/, exception.message
      end

    end

    context "with server" do
      setup do
        @server = SimpleTCPServer.new(2000)
        @server_name = 'localhost:2000'
      end

      teardown do
        @server.stop if @server
      end

      # Not sure how to automatically test this, need a server that is running
      # but does not respond in time to a connect request
      #
      #should "timeout on connect" do
      #  exception = assert_raise ResilientSocket::ConnectionTimeout do
      #    ResilientSocket::TCPClient.new(
      #      :server          => @server_name,
      #      :connect_timeout => 0.1
      #    )
      #  end
      #  assert_match /Timedout after/, exception.message
      #end

      context "with client connection" do
        setup do
          @read_timeout = 3.0
          @client = ResilientSocket::TCPClient.new(
            :server          => @server_name,
            :read_timeout    => @read_timeout
          )
        end

        def teardown
          @client.close
        end

        should "successfully send and receive data" do
          request = { 'action' => 'test1' }
          @client.send(BSON.serialize(request))
          reply = read_bson_document(@client)
          assert_equal 'test1', reply['result']
        end

        should "timeout on receive" do
          request = { 'action' => 'sleep', 'duration' => @read_timeout + 0.5}
          @client.send(BSON.serialize(request))

          exception = assert_raise ResilientSocket::ReadTimeout do
            # Read 4 bytes from server
            @client.read(4)
          end
          assert_match /Timedout after #{@read_timeout} seconds trying to read from #{@server_name}/, exception.message
        end

        should "retry on connection failure" do
          attempt = 0
          reply = @client.retry_on_connection_failure do
            request = { 'action' => 'fail', 'attempt' => (attempt+=1) }
            @client.send(BSON.serialize(request))
            # Note: Do not put the read in this block if it should never send the
            #       same request twice to the server
            read_bson_document(@client)
          end

#          exception = assert_raise ResilientSocket::ConnectionFailure do
#            # Read 4 bytes from server
#            @client.read(4)
#          end
#          assert_match /EOFError/, exception.message

          #@client.send(BSON.serialize(request))
          #reply = read_bson_document(@client)
          assert_equal 'fail', reply['result']
        end

        #      context "on automatic retry" do
        #        should "raise exception when cannot reach server" do
        #        end
        #      end

      end
    end

  end
end