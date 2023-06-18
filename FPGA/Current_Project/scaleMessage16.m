% Scale the message to 8 bits signed

function [raw_message, divisor] = scaleMessage16(raw_message_float)
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
    if num_bits_needed > 15
        arr_div_a = 2^(num_bits_needed-15)*ones(size(raw_message_float,1), size(raw_message_float,2));
        raw_message_scaled = raw_message_float./arr_div_a;
        divisor = 2^(num_bits_needed-7);
    end
    raw_message = int16(raw_message_scaled);
    
end