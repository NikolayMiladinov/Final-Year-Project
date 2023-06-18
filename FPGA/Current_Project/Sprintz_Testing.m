% -------- Load data -----------
edf_jh1 = edfread('JH1.edf');
edf_jh2 = edfread('JH2.edf');
edf_jh3 = edfread('JH3.edf');
edf_jh21 = edfread('JH21.edf');
edf_array = {edf_jh1 edf_jh2 edf_jh3 edf_jh21};
%%

num_rep = 10;
cmp_ratio_size = zeros(num_rep,2, size(edf_array,2));

rng(3); % Specify seed for random data generator
for k=1:size(edf_array,2)
    curr_edf = edf_array{k};
    for i=1:num_rep
        channel = round(randi(size(curr_edf,2)));
        range_edf = sort(round(randi(size(curr_edf,1),1,2)));
        data_arr = cell2mat(table2array(curr_edf(range_edf(1):range_edf(2),channel))).';
        [data_arr, big_dif] = scaleMessage(data_arr);
        sim_compress = simCompressSprintz(data_arr);
        cmp_ratio_size(i,:,k) = [size(data_arr,2)/size(sim_compress,2) size(data_arr,2)];
        % if cmp_ratio_size(i,1,1) > 6
        %     fprintf("Channel, range: %d, %d, %d \n", channel, range_edf(1), range_edf(2))
        % end
    end
end

%%
cmp_full_cells = {};
for c=1:size(edf_array,2)
    cmp_arr = zeros(size(edf_array{c},2),4);
    cmp_full_cells = [cmp_full_cells cmp_arr];
end

for k=1:size(edf_array,2)
    curr_edf = edf_array{k};
    for i=1:size(curr_edf,2)
        data_arr = cell2mat(table2array(curr_edf(1:size(curr_edf,1),i))).';
        [max_edf_val, idx_max_edf_val] = max(data_arr);
        [min_edf_val, idx_min_edf_val] = min(data_arr);
        if max_edf_val>127 || min_edf_val<-128
            [data_arr, div_edf] = scaleMessage16(data_arr);
            sim_compress = simCompressSprintz16(data_arr);
            cmp_full_cells{k}(i,:) = [2*size(data_arr,2)/size(sim_compress,2) 2*size(data_arr,2)/(size(sim_compress,2)-size(data_arr,2)*4/64) size(data_arr,2) div_edf];
        else
            [data_arr, div_edf] = scaleMessage(data_arr);
            sim_compress = simCompressSprintz(data_arr);
            cmp_full_cells{k}(i,:) = [size(data_arr,2)/size(sim_compress,2) 2*size(data_arr,2)/(size(sim_compress,2)-size(data_arr,2)*5/64) size(data_arr,2) div_edf];
        end
        
    end
end

%%
comp_ratio_array = [cmp_full_cells{1}; cmp_full_cells{2}; cmp_full_cells{3}; cmp_full_cells{4}];
av_comp_ratio = mean(comp_ratio_array(:,1));
av_pot_comp_ratio = mean(comp_ratio_array(:,2));

b_fit = polyfit(cmp_ratio_size(:,2,1), cmp_ratio_size(:,1,1), 1);
b_fit_arr = b_fit(1) .*cmp_ratio_size(:,2,1)  + b_fit(2);


% scatter(cmp_ratio_size(:,2,1), cmp_ratio_size(:,1,1),10,"red", "filled")
% hold on;
% plot(cmp_ratio_size(:,2,1),b_fit_arr)
% hold off;


%%
data_arr_16bit = cell2mat(table2array(edf_jh21(:,20))).';
[data_arr_16bit, div16] = scaleMessage16(data_arr_16bit);

message_delta16 = data_arr_16bit;
prev_val = message_delta16(1);
current_val = 0;

% The first value of the raw message remains the same
% Every following value is y = x_i - x_(i-1)
for i = 2:size(data_arr_16bit,2)
    current_val = message_delta16(i);
    message_delta16(i) = message_delta16(i) - prev_val;
    prev_val = current_val;
end


sim_compress_16bit = simCompressSprintz16(data_arr_16bit);
fprintf("Compression ratio: %f \n", 2*size(data_arr_16bit,2)/size(sim_compress_16bit,2))
% sim_decom_16bit = decompressSprintz16(sim_compress_16bit);

% if sim_decom_16bit == data_arr_16bit
%     fprintf("Successful 16-bit decompression \n")
% end