# Copyright, 2018, by Samuel G. D. Williams. <http://www.codeotaku.com>
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'falcon/command/virtual'

RSpec.shared_context Falcon::Command::Virtual do
	let(:examples_root) {File.expand_path("../../../examples", __dir__)}
	
	let(:command) {
		described_class[
			"--bind-insecure", "http://localhost:8080",
			"--bind-secure", "https://localhost:8443",
			*options,
		]
	}
	
	let(:container) {command.run(true)}
	
	around do |example|
		# Wait for the container to start...
		container
		
		# TODO some kind of more reliable synchronisation:
		# until File.exist? "server.ipc"
		sleep(4)
		
		begin
			example.run
		ensure
			container.stop(false)
		end
	end
	
	let(:insecure_client) {Async::HTTP::Client.new(command.insecure_endpoint, retries: 0)}
end

RSpec.describe Falcon::Command::Virtual do
	context "with example sites" do
		let(:options) {[
			File.expand_path("hello/falcon.rb", examples_root),
			File.expand_path("beer/falcon.rb", examples_root),
		]}
		
		include_context Falcon::Command::Virtual
		
		it "gets redirected from insecure to secure endpoint" do
			request = Protocol::HTTP::Request.new("http", "hello.localhost", "GET", "/index")
			
			Async do
				response = insecure_client.call(request)
				
				expect(response).to be_redirection
				expect(response.headers['location']).to be == "https://hello.localhost:8443/index"
				
				response.close
			end
		end
		
		shared_examples_for Falcon::Command::Virtual do
			let(:host_endpoint) {command.host_endpoint("hello.localhost")}
			let(:secure_client) {Async::HTTP::Client.new(host_endpoint, retries: 0)}
			
			it "gets valid response from secure endpoint" do
				request = Protocol::HTTP::Request.new("https", "hello.localhost", "GET", "/index")
				
				expect(request.authority).to be == "hello.localhost"
				
				Async do
					response = secure_client.call(request)
					
					expect(response).to be_success
					expect(response.read).to be == "Hello World"
					
					secure_client.close
				end.wait
			end
		end
		
		context "HTTP/1.0" do
			let(:protocol) {Async::HTTP::Protocol::HTTP10}
			include_examples Falcon::Command::Virtual
		end
		
		context "HTTP/1.1" do
			let(:protocol) {Async::HTTP::Protocol::HTTP11}
			include_examples Falcon::Command::Virtual
		end
		
		context "HTTP/2" do
			let(:protocol) {Async::HTTP::Protocol::HTTP2}
			include_examples Falcon::Command::Virtual
		end
	end
end
