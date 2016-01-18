
%% case where the controls are in separate files
toy3_input_data = '../../INPUT/toy_example_input3_data.tsv';
toy3_input_ctrl = '../../INPUT/toy_example_input3_ctrl.tsv';
toy3_input_time0 = '../../INPUT/toy_example_input3_time0.tsv';

output_tag = '../../OUTPUT/MATLAB_results_input3.tsv';

% evaluate the GR value for the data
[t_GRvalues_3, t_GRmetrics_3] = GRmetrics(output_tag, toy3_input_data, ...
    toy3_input_ctrl, toy3_input_time0);


%% reference data

t_GRvalues_ref = sortrows(readtable('../../OUTPUT/toy_example_output.tsv', ...
    'filetype','text','delimiter','\t'));
t_GRmetrics_ref = sortrows(readtable('../../OUTPUT/toy_example_DrugParameters.tsv', ...
    'filetype','text','delimiter','\t'));
t_GRmetrics_ref.cell_line = categorical(t_GRmetrics_ref.cell_line);
t_GRmetrics_ref.agent = categorical(t_GRmetrics_ref.agent);

%% check the GR value matching
t_join = join(t_GRvalues_3(:,[1:6 end]),t_GRvalues_ref(:,[1:6 end]), 'keys', 1:6);
assert(all(abs(t_join.GRvalue_left-t_join.GRvalue_right)<1e-5))

%% check the fit parameters are reasonnably close
%   because of added noise, they will not match exaclty
t_means = grpstats(t_GRmetrics_3(:,[1:2 7 9:11]), 1:2, @mean);
t_join = join(t_means,t_GRmetrics_ref, 'keys', 1:2);
for i=3:width(t_GRmetrics_ref)
    disp([t_GRmetrics_ref.Properties.VariableNames(i) ' '
        {'------------' ' '}
        t_join.Properties.RowNames ...
        num2cell(t_join.(['mean_' t_GRmetrics_ref.Properties.VariableNames{i}]) - ...
        t_join.(t_GRmetrics_ref.Properties.VariableNames{i}))])
end