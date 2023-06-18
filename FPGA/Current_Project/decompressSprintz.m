function decompressed_message = decompressSprintz(compressed_message)
    decompressed_message = uint16.empty;
    pack_byte_width = 0;
    check_width = 1;
    data_bits_left = 0;
    bytes_to_unpack = 0;
    
    
    % Unpack array
    for i=1:size(compressed_message,2)
        pack_bits_left = 8;
        % First byte is always a header
        % First check if it's a header
        % header of 0 is followed by another header
        if check_width == 1
            pack_byte_width = compressed_message(i);
            if pack_byte_width == 7
                pack_byte_width = 8;
            end
            check_width = 0;
            data_bits_left = pack_byte_width;
            bytes_to_unpack = pack_byte_width;
            
        else 
            % Unpack all the whole/previous bytes first
            while pack_bits_left >= data_bits_left
                bit_array = bitget(compressed_message(i),pack_bits_left:-1:(pack_bits_left-data_bits_left+1));
                
                % If unpacking a previous data byte (i.e. 2 bits were in
                % previous byte and there are 3 bits left), shift the previous
                % bits by the number of bits left and add what was left
                if data_bits_left ~= pack_byte_width
                    % In this case, the last recorded byte should be updated
                    decompressed_message(end) = bitshift(decompressed_message(end),data_bits_left);
                    decompressed_message(end) = decompressed_message(end) + uint16(bit2int(bit_array',size(bit_array,2)));
                else
                    decompressed_message = [decompressed_message uint16(bit2int(bit_array',size(bit_array,2)))];
                end
                
                pack_bits_left = pack_bits_left - data_bits_left;
                data_bits_left = pack_byte_width;
            end
            % Unpack the partial bytes
            if pack_bits_left > 0
                bit_array = bitget(compressed_message(i),pack_bits_left:-1:1);
                decompressed_message = [decompressed_message uint16(bit2int(bit_array',size(bit_array,2)))];
                data_bits_left = data_bits_left - pack_bits_left;
            end
            pack_bits_left = 8;
            % Bytes to unpack are set after each header
            % At this stage the byte is always unpacked
            bytes_to_unpack = bytes_to_unpack - 1;
            if bytes_to_unpack == 0
                check_width = 1;
            end
        end
    
        % Check for header of 0
        if pack_byte_width == 0
            check_width = 1;
            decompressed_message = [decompressed_message uint16(zeros(1,8))];
        end
    end
    
    decompressed_message = uint8(decompressed_message);
    decompress_zigzag = int8(zeros(1,size(decompressed_message,2)));

    % Zigzag decode
    for i = 1:size(decompress_zigzag,2)
        if mod(decompressed_message(i),2)==1
            decompress_zigzag(i) = int8((decompressed_message(i) + 1)/2);
            decompress_zigzag(i) = -decompress_zigzag(i);
        else
            decompress_zigzag(i) = int8(decompressed_message(i)/2);
        end
    end

    decompressed_message = int8(decompress_zigzag);

    % Delta decode
    for i=2:size(decompressed_message,2)
        decompressed_message(i) = decompressed_message(i-1) + decompressed_message(i);
    end
    
    decompressed_message = int8(decompressed_message);
end

