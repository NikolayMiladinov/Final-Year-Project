% UART Parameters
COM_PORT = "COM7"; % Specify COM port
BAUD_RATE = 9600;  % Specify Baud rate

% Specify the transfer size (up to 13 bits <=> 4095)
N_data = uint16(2048);
% Split N_data into 2 bytes using a bitmask and right shift
transfer_size = [uint8(bitand(bitshift(N_data,-8),0xFFu16)) uint8(bitand(N_data,0xFFu16))];
fprintf("Transfer size is: %d \n", N_data);

% First byte sent is the command
% 33 means 2 bytes for transfer size and then the data will be sent
Data_command = uint8(33);

% Data
rng(3); % Specify seed for random data generator
% Generates N number of random bytes in the range 0 to 255
rand_data = (uint8(round(255.*rand(N_data,1)))).';

message = unicode2native('Hello, this is a test. 40 chars message.');
% Combine the command, transfer size and message
% This is command specific (currently there is only 1 command)
compl_message = [Data_command, transfer_size, rand_data];



%% 
message_received = []; % initialise array to store received UART info
s = serialport(COM_PORT, BAUD_RATE); % Start the serial connection
flush(s); % clear the UART buffers

t_start = tic; % Start a timeout timer

write(s, compl_message, "uint8"); % Send the UART message
fprintf("Writing complete \n");

while 1 % Wait to receive message
   if s.NumBytesAvailable > 0
        % Store incoming message
        fprintf("Started receiving \n");
        message_received = read(s, N_data, "uint8");
        break % Stop waiting
   elseif toc(t_start)>15
        fprintf("Timeout \n");
        break % Stop waiting if more than X seconds pass
   end
end

s = []; % Clears the UART port/ breaks the connection
% If not cleared, next time there will be an error

% Check if the lengths of the messages are the same
% If not the same and try to compare them => error
if length(message_received) == length(rand_data)
    if message_received == rand_data
        fprintf("Successful \n")
    else 
        fprintf("Different message received: %c \n",message_received)
    end
else 
    fprintf("Different size received: %d \n",message_received)
end
