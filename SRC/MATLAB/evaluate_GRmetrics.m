function t_out = evaluate_GRmetrics(t_in)

keys = setdiff(t_in.Properties.VariableNames, {'concentration', ...
    'cell_count' 'cell_count__ctrl' 'cell_count__time0' 'GRvalue'}, 'stable');
MetricsNames = {'GR50' 'GRmax' 'GR_AUC' 'EC50' 'GRinf' 'Hill' 'r2' 'pval'};

% convert string keys to categorical
for ik = keys
    if iscellstr(t_in.(ik{:}))
        t_in.(ik{:}) = categorical(t_in.(ik{:}));
    end
end

% assign the t_out table
t_out = unique(t_in(:,keys));
t_out = [t_out array2table(NaN(height(t_out), length(MetricsNames)),...
    'variablenames', MetricsNames)];

warn_flag = true;
for i=1:height(t_out)
    if mod(i,floor(height(t_out)/10))==0
        fprintf('%.0f%% ', 100*i/height(t_out))
    end
    
    idx = table_equality(t_out(i,:), t_in, keys);
    
    if sum(idx)<=4 && warn_flag
        warning('less than 4 concentrations for some conditions --> no fit')
        warn_flag = false;
    end
    GRmetrics = fit_dose_response(t_in(idx,:));
    
    for iM = MetricsNames, t_out.(iM{:})(i) = GRmetrics.(iM{:}); end
end

fprintf('\n');
end


function idx = table_equality(t1, t_all, keys)
% find the indices in table t_all where keys equal row t1
idx = all( cell2mat(cellfun(@(x) t1.(x) == t_all.(x), keys, ...
    'uniformoutput', false)), 2);
end


function GRmetrics = fit_dose_response(t_in)
% fit a sigmoidal function to the data and output the results as a struct
%   test the significance against a flat fit (cutoff is 0.05)
t_ = sortrows(t_in(:,{'concentration' 'GRvalue'}), 1, 'ascend');
c = t_.concentration;
g = t_.GRvalue;

pcutoff = 0.05; % for the F-test of the sigmoidal fit

if height(t_)<2
    error('Need at least two different concentrations per condition')
end
% define output structure
GRmetrics = struct( ...
    'GR50', NaN, ...
    'GRmax', min(g(end-[1 0])), ... % robust minimum on the last 2 concentrations
    'GRinf', NaN, ...
    'Hill', NaN, ...
    'EC50', NaN, ...
    'r2', NaN, ...
    'GR_AUC', sum( (1-(g(2:end)+g(1:(end-1)))/2) .* diff(log10(c))) / ...
    diff(log10(c([1 end]))) ... % normalized version of the AUC
    );

if length(c)<=4
    return
end

% parameters : GRinf  EC50   Hill
priors = [.1 median(c) 2];
ranges = [
    -1 1                    % GRinf
    min(c)*1e-2 max(c)*1e2  % EC50
    .1 5                    % Hill
    ]';

% fit will be perfomed in the log10 domain (more precise)
ranges(:,2) = -log10(ranges([2 1],2));
priors(2) = -log10(priors(2));

% sigmoidal fit
[fit_result, gof] = sigmoidal_fit(c, g, ranges, priors);
% flat fit (for F-test)
[fit_res_flat, gof_flat] = flat_fit(c, g, ranges, priors);


% F-test for the significance of the sigmoidal fit
Npara = 3; % N of parameters in the growth curve
Npara_flat = 1; % F-test for the models
RSS2 = gof.sse;
RSS1 = gof_flat.sse;
df1 = (Npara -Npara_flat);
df2 = (length(g) -Npara +1);
F = ( (RSS1-RSS2)/df1 )/( RSS2/df2 );
GRmetrics.pval = 1-fcdf(F, df1, df2);


if GRmetrics.pval>=pcutoff || isnan(RSS2) % nonsiggnificant or failed fit
    % flat fit parameters
    if fit_res_flat.a > .5
        GRmetrics.GR50 = +Inf;
    else
        GRmetrics.GR50 = -Inf;
    end
    GRmetrics.EC50 = 0; % such that sigmoidal fit function can be evaluated
    GRmetrics.Hill = .01; % arbitrary low (but not equal to 0)
    GRmetrics.GRinf = fit_res_flat.a; % robust minimum on the last 2 concentrations
    GRmetrics.r2 = gof_flat.rsquare;
    
else % significant sigmoidal fit
    
    % fit parameters
    GRmetrics.GRinf = fit_result.a;
    GRmetrics.Hill = fit_result.c;
    GRmetrics.EC50 = 10^-fit_result.b;
    GRmetrics.r2 = gof.rsquare;
    
    % interpolation for GR50; allow extrapolation up to one order of magnitude
    % above and below measured range
    extrapolrange = 10;
    xc = 10.^[log10(min(c)/extrapolrange) log10(max(c)*extrapolrange)];
    
    fit_growth = fit_result(xc);
    GRmetrics.GR50 = GRmetrics.EC50*( ( ( (1-GRmetrics.GRinf)/(.5-GRmetrics.GRinf) )-1) ...
        ^(1/GRmetrics.Hill)); % solving the sigmoidal function to get GR(GR50)=0.5
    
    if any(fit_growth<.5) && any(fit_growth>.5) % inter/extrapolation is fine
    elseif all(fit_growth>.5)
        if GRmetrics.GR50>extrapolrange*max(c) || imag(GRmetrics.GR50)~=0
            GRmetrics.GR50 = Inf; % extrapolated value above concentraion range
        end
    elseif all(fit_growth<.5)
        if GRmetrics.GR50<min(c)/extrapolrange || imag(GRmetrics.GR50)~=0
            GRmetrics.GR50 = -Inf; % extrapolated value below concentraion range
        end
    else
        GRmetrics.GR50 = NaN; % this should not occur
        warning('undefined GR fit')
    end
    
end
end

function [fit_result, gof] = sigmoidal_fit(c, g, ranges, priors)
% sigmoidal fit function
fitopt = fitoptions('Method','NonlinearLeastSquares',...
    'Lower', ranges(1,:),...
    'Upper', ranges(2,:),...
    'Startpoint', priors);
% sigmoidal function for concentrations in the log domain
f = fittype('a + (1-a) ./ ( 1 + (x*(10.^b)).^c)', 'options', fitopt);
[fit_result, gof] = fit(c, g, f);
end


function [fit_result, gof] = flat_fit(c, g, ranges, priors)
% flat fit function (special case of sigmoidal fit)
fitopt = fitoptions('Method','NonlinearLeastSquares',...
    'Lower',ranges(1,1),...   % min Emax
    'Upper',1.2,...   % max E0
    'Startpoint',priors(1));
f = fittype('a+0*x','options',fitopt);
[fit_result, gof] = fit(c, g,f);
end


