require 'redis'
require 'optparse'

def valid_option_keys?(opts_keys)
  return true if opts_keys.eql? [:host, :port, :password]
  return true if opts_keys.eql? [:url]
  false
end

options = {}

option_parser = OptionParser.new do |parser|
  parser.banner = "Usage: ruby example.rb [--url <url>]|[--host <host> --port <port>]" \
                  " --password <password>"
  parser.on('--url URL','Redis URL') { |u| options[:url] = u }
  parser.on('--host HOST','Redis host') { |h| options[:host] = h }
  parser.on('--port PORT', 'Redis port') { |p| options[:port] = p }
  parser.on('--password PASSWORD','Redis password') { |p| options[:password] = p }
end

option_parser.parse!

unless valid_option_keys? options.keys
  puts option_parser
  exit
end

client = Redis.new(options.merge({ssl: true}))

key = 'RubyRedisExample'

client.set(key, 'Ruby Example')
value = client.get(key)
  
puts "The value for key '#{key}' is '#{value}'"
