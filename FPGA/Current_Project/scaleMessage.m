% Scale the message to 8 bits signed

function [raw_message, divisor] = scaleMessage(raw_message_float)
    % Get min and max of input array
    [max_val_raw, ~] = max(raw_message_float);
    [min_val_raw, ~] = min(raw_message_float);
    % Calculate the number of bits necessary to represent the data
    num_bits_needed = 0;
    if max_val_raw > abs(min_val_raw)
        num_bits_needed = ceil(log2(max_val_raw+1));
    else
        num_bits_needed = ceil(log2(abs(min_val_raw)+1));
    end
    
    raw_message_scaled = raw_message_float;
    % If the min/max value of the message cannot be represented by 8 bits
    % signed, then do right arithmetic shift by num_bits_needed+1-8
    % +1 is for sign
    divisor = 0;
    if num_bits_needed > 7
        arr_div_a = 2^(num_bits_needed-7)*ones(size(raw_message_float,1), size(raw_message_float,2));
        raw_message_scaled = raw_message_float./arr_div_a;
        divisor = 2^(num_bits_needed-7);
    end
    raw_message = int8(raw_message_scaled);
    
    % Calculate the biggest difference between two consecutive values
    % if it is more than 127 or less than -128, that will be a problem when
    % compressing the message
    biggest_diff = int16(0);
    for i=2:size(raw_message,2)
        current_delta_t = abs(int16(raw_message(i))-int16(raw_message(i-1)));
        if current_delta_t > biggest_diff
            biggest_diff = current_delta_t;
        end
    end
end