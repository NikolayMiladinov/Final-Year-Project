% UART Parameters
COM_PORT = "COM7"; % Specify COM port
BAUD_RATE = 9600;  % Specify Baud rate
COMPRESS = 1;

% Specify the transfer size (up to 13 bits <=> 4095)
N_data = int16(2048);
% Split N_data into 2 bytes using a bitmask and right shift
transfer_size = [int8(bitand(bitshift(N_data,-8),0xFFs16)) int8(bitand(N_data,0xFFs16))];
fprintf("Transfer size is: %d \n", N_data);

% First byte sent is the command
% 33 means 2 bytes for transfer size and then the data will be sent
Data_command = int8(33);

% Data
rng(3); % Specify seed for random data generator
% Generates N number of random bytes in the range 0 to 255
rand_data = (uint8(round(255.*rand(N_data,1)))).';
message_40chars = unicode2native('Hello, this is a test. 40 chars message.');

% EDF Data
channel = 1;
range_edf = [1 8];
data_edf = edfread('JH3.edf'); % read data from file
% Get only the data wanted -> range(1) to range(2), channel#
arr_edf = table2array(data_edf(range_edf(1):range_edf(2),channel));

% transform the edf data into 1xN array
raw_message_float = transpose(arr_edf{1,1});
for i = 2:(range_edf(2)+1-range_edf(1))
    raw_message_float = [raw_message_float, transpose(arr_edf{i,1})]; %#ok<AGROW>
end

% Since the edf data is to be sent via UART with 8-bit precision,
% the message must first be scaled
[raw_message, biggest_diff] = scaleMessage(raw_message_float);

% Combine the command, transfer size and message
% This is command specific (currently there is only 1 command)
if COMPRESS == 1
    compl_message = [Data_command, transfer_size, raw_message];
else
    compl_message = [uint8(Data_command), uint8(transfer_size), rand_data];
end

%%

simulated_compression = simCompressSprintz(raw_message);
simulated_delta_encoding = deltaEncode(raw_message);
fprintf("Compression ratio: %f \n", size(raw_message,2)/size(simulated_compression,2))
fprintf("Potential optimised compression ratio: %f, \n", size(raw_message,2)/(size(simulated_compression,2)-size(raw_message,2)*5/64))
simulated_decompressed_message = decompressSprintz(simulated_compression);
if simulated_decompressed_message == raw_message
    fprintf("Simulated decompression successfull \n")
end

%% 
message_received = []; % initialise array to store received UART info
s = serialport(COM_PORT, BAUD_RATE); % Start the serial connection
flush(s); % clear the UART buffers

t_start = tic; % Start a timeout timer

write(s, compl_message, "int8"); % Send the UART message
fprintf("Writing complete \n");

while 1 % Wait to receive message
   if s.NumBytesAvailable > 0
        % Store incoming message
        fprintf("Started receiving \n");
        message_received = read(s, size(simulated_compression,2), "uint8");
        break % Stop waiting
   elseif toc(t_start)>15
        fprintf("Timeout \n");
        break % Stop waiting if more than X seconds pass
   end
end

message_received_compressed = message_received;

if COMPRESS == 1
    message_received = decompressSprintz(message_received); 
end
s = []; % Clears the UART port/ breaks the connection
% If not cleared, next time there will be an error

% Check if the lengths of the messages are the same
% If not the same and try to compare them => error
if length(message_received) == length(rand_data)
    if message_received == raw_message
        fprintf("Successful \n")
    else 
        fprintf("Different message received: %d \n",message_received)
    end
else 
    fprintf("Different size received: %d \n",message_received)
end

%%

% Check if the received compressed message is the same as the simulated in
% MATLAB one
if message_received_compressed==simulated_compression
    fprintf("Message received was correctly compressed \n")
else
    for i=1:size(message_received_compressed,2)
        if message_received_compressed(i) ~= simulated_compression(i)
            fprintf("Different encoding at index: %d \n",i)
        end
    end
end

%%
% Get the delta encoding of a message
function message_delta = deltaEncode(raw_message)
    message_delta = raw_message;
    prev_val = message_delta(1);
    current_val = 0;
    
    % The first value of the raw message remains the same
    % Every following value is y = x_i - x_(i-1)
    for i = 2:size(raw_message,2)
        current_val = message_delta(i);
        message_delta(i) = message_delta(i) - prev_val;
        prev_val = current_val;
    end
end

%%

% see compression vs compressed length
% calculate potential compression savings from more dimensions
% track # of occurrences for each width
% with 8 dimensions, 3 headers + 8*8, with 1 dimension its 8 headers + 8*8
% so 5 saved bytes per block, therefore, only need the block count
% N_blocks*8*8 = original data size
% with 8 dimensions -> compressed with 1-dimension - N_blocks*7
% saving per dimension is N_blocks*5/8
% N_blocks is just orig_data_size/8



% 10 tests for same setup but different data
% 10 tests for same data, but different clock setup
% 1,2,5,10,20,40,60,80,100,120,140,160