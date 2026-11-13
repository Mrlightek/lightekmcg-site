# Deterministic HTTP Rspamd stand-in for the isolated protocol test process.
# Scanner response validation tests still stub HTTP directly to exercise errors.
require 'minitest/autorun'
require 'socket'
require 'json'
mail_spam_fixture_server = TCPServer.new('127.0.0.1', 0)
previous_spam_fixture_url = ENV['LIGHTEK_MAIL_RSPAMD_URL']
ENV['LIGHTEK_MAIL_RSPAMD_URL'] = "http://127.0.0.1:#{mail_spam_fixture_server.addr[1]}/checkv2"
mail_spam_fixture_thread = Thread.new do
  loop do
    socket = mail_spam_fixture_server.accept
    socket.gets
    length = 0
    while (line = socket.gets) && line != "\r\n"
      length = line.split(':',2).last.to_i if line.downcase.start_with?('content-length:')
    end
    socket.read(length) if length > 0
    body = JSON.generate(action:'no action',score:0.5)
    socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
    socket.close
  end
rescue IOError, Errno::EBADF
  nil
end
mail_spam_fixture_thread.report_on_exception = false
Minitest.after_run do
  mail_spam_fixture_server.close
  mail_spam_fixture_thread.kill
  mail_spam_fixture_thread.join
  previous_spam_fixture_url ? ENV['LIGHTEK_MAIL_RSPAMD_URL'] = previous_spam_fixture_url : ENV.delete('LIGHTEK_MAIL_RSPAMD_URL')
end
