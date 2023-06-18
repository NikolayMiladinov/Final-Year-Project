% --------------- Simulate Compression ---------------------

function message_packed = simCompressSprintz(raw_message)

    % ---------- Delta encoding ----------
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
    
    
    % ---------- Zigzag encoding ----------
    
    % Initialise new array
    message_zigzag = uint8(zeros(1,size(raw_message,2)));
    
    % y_i = abs(x_i)*2 
    % If x_i < 0  ----> y_i = y_i - 1
    for i = 1:size(raw_message,2)
        message_zigzag(i) = uint8(abs(2*int16(message_delta(i))));
        if sign(message_delta(i))==-1
            message_zigzag(i) = message_zigzag(i) - 1;
        end
    end
    
    % ---------- Bit packing ----------
    
    % Create a mask for every n MSB bits
    % first array variable is 255 = 1111 1111
    % second one is 254 = 1111 1110 and so on
    % last one is 0
    mask_arr = uint8(zeros(1,9));
    for i=1:8
        mask_arr(i) = uint8(255 - bitshift(1, i-1) + 1);
    end
    
    % initialise packed array, size is unknown
    message_packed = uint8.empty;
    
    leading_zeros = 8; % assume best case scenario
    % fprintf("Begin packing \n")
    
    % For loop for every 8 bytes
    for i=1:8:size(raw_message,2)
        leading_zeros = 8; % For every new block, reset the leading_zeros
    
        % Calculate the leading zeros
        for j=0:7
            if leading_zeros > 1 % Stop when leading zeros is 1 or 0 because they are treated the same
                for k=leading_zeros:-1:0 % Only check the worst scenarios for every byte of the block
                    if bitand(message_zigzag(i+j),mask_arr(9-k)) == 0
                        leading_zeros = k;
                        break % Break when the worst case leading zeros is calculated
                    end
                end
            end
        end
        
        n_pack_size = 8 - leading_zeros; % This number indicates how many bits should be taken from each byte
        if leading_zeros <= 1 % treat the case of 1 and 0 leading zeros same way
            n_pack_size = 8;
        end
    
        % if n_pack_size == 0
        %     fprintf("Pack size of 0 \n")
        % end
    
        % Add the number of bits per byte as a header to the block
        if n_pack_size >=7
            message_packed = [message_packed, uint8(7)];
        else
            message_packed = [message_packed, uint8(n_pack_size)];
        end

        % Initialise the packed array, which is of known size
        pack8 = uint8(zeros(1,n_pack_size)); % Can be an empty array as well
        % fprintf("packing \n")
    
        track_data_byte = 1; % tracks how many bytes have been packed
        pack_bits_left = 8; % tracks number of bits left in the current packed byte
        data_bits_left = n_pack_size; % tracks how many bits are left from the current data byte
    
        if n_pack_size > 0 % Only pack if there are non-zero values
            for j=1:n_pack_size % Loop through every byte in packed block
                % Check if the current packed byte can fit the whole or
                % leftover part of the current data byte
                while pack_bits_left >= data_bits_left && track_data_byte < 9 % only continue packing if there are more data bytes (total of 8)
                    % Create the array of the bits that need to be packed
                    val_bits = bitget(message_zigzag(i+track_data_byte-1),data_bits_left:-1:1);
    
                    % Pack the bits into the packed byte one by one 
                    % couldn't find a better way
                    for bit_pos=0:(data_bits_left-1)
                        pack8(j) = bitset(pack8(j), pack_bits_left-bit_pos, val_bits(bit_pos+1));
                    end
                    pack_bits_left = pack_bits_left - data_bits_left; % update remaining bits left
                    track_data_byte = track_data_byte + 1; % increase the count for the data bytes
                    data_bits_left = n_pack_size; % update the data bits left
                end
                % Same as previously but for the case where the packed bits
                % left are less than the data bits left
                % Also check if the packed bits left are more than 0
                if track_data_byte < 9 && pack_bits_left > 0
                    val_bits = bitget(message_zigzag(i+track_data_byte-1),data_bits_left:-1:(data_bits_left - pack_bits_left + 1));
                    for bit_pos=0:(pack_bits_left-1)
                        pack8(j) = bitset(pack8(j), pack_bits_left-bit_pos, val_bits(bit_pos+1));
                    end
                    data_bits_left = data_bits_left - pack_bits_left;
                end
                % The above steps ensure every byte is fully packed
                % The packed bits left should be 0 at this point
                pack_bits_left = 8; % reset the packed bits left for the next loop cycle
            end
        end
        % Add the packed block
        message_packed = [message_packed, pack8]; 
    end
end
