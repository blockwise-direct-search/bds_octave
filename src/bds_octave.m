function [xopt, fopt, exitflag, output] = bds_octave(fun, x0, options)
%BDS_OCTAVE solves unconstrained optimization problems without using derivatives by 
%blockwise direct search methods. 
%
%   BDS_OCTAVE supports in MATLAB R2017b or later.
%   
%   XOPT = BDS_OCTAVE(FUN, X0) returns an approximate minimizer XOPT of the function FUN, 
%   starting the calculations at X0. FUN must accept a vector input X and return a scalar.
%
%   XOPT = BDS_OCTAVE(FUN, X0, OPTIONS) performs the computations with the options in OPTIONS. 
%   OPTIONS should be a structure with the following fields.
%
%   Algorithm                   Algorithm to use. It can be "cbds" (cyclic blockwise direct
%                               search) "pbds" (randomly permuted blockwise direct search), 
%                               "rbds" (randomized blockwise direct search), "ds" (the classical 
%                               direct search), "pads" (parallel blockwise direct search). 
%                               "scbds" (symmetric blockwise direct search). Default: "cbds".
%   num_blocks                  Number of blocks. A positive integer. Default: n if Algorithm 
%                               is "cbds", "pbds", or "rbds", 1 if Algorithm is "ds".
%   MaxFunctionEvaluations      Maximum of function evaluations. A positive integer.
%   direction_set               A matrix whose columns will be used to define the polling
%                               directions. If options does not contain direction_set, then 
%                               the polling directions will be {e_1, -e_1, ..., e_n, -e_n}. 
%                               Otherwise, direction_set should be a matrix of n rows, and 
%                               the polling directions will be {d_1, -d_1, ..., d_m, -d_m}, 
%                               where d_i is the i-th column of direction_set, and m is the
%                               number of columns of direction_set. If necessary, we will 
%                               first extend direction_set by adding some columns to make 
%                               sure that rank(direction_set) = n, so that the polling 
%                               directions make a positive spanning set. 
%                               See get_direction_set.m for details.
%   expand                      Expanding factor of step size. A real number no less than 1.
%                               Default: 2.
%   shrink                      Shrinking factor of step size. A positive number less than 1.
%                               Default: 0.5.
%   forcing_function            The forcing function used for deciding whether the step achieves
%                               a sufficient decrease. A function handle. 
%                               Default: @(alpha) alpha^2. See also reduction_factor. 
%   reduction_factor            Factors multiplied to the forcing function when deciding 
%                               whether the step achieves a sufficient decrease. 
%                               A 3-dimentional vector such that 
%                               reduction_factor(1) <= reduction_factor(2) <= reduction_factor(3),
%                               reduction_factor(1) >= 0, and reduction_factor(2) > 0.
%                               reduction_factor(0) is used for deciding whether to update 
%                               the base point; 
%                               reduction_factor(1) is used for deciding whether to shrink 
%                               the step size; 
%                               reduction_factor(2) is used for deciding whether to expand 
%                               the step size.
%                               Default: [0, eps, eps]. See also forcing_function.
%   StepTolerance               Lower bound of the step size. If the step size is smaller 
%                               than StepTolerance, then the algorithm terminates. 
%                               A (small) positive number. Default: 1e-10.
%   ftarget                     Target of the function value. If the function value is 
%                               smaller than or equal to ftarget, then the algorithm terminates. 
%                               A real number. Default: -Inf.
%   polling_inner               Polling strategy in each block. It can be "complete" or 
%                               "opportunistic". Default: "opportunistic".
%   cycling_inner               Cycling strategy employed within each block. It is used only 
%                               when polling_inner is "opportunistic". It can be 0, 1, 2, 3, 4.
%                               See cycling.m for details. Default: 3.
%   with_cycling_memory         Whether the cycling strategy within each block memorizes 
%                               the history or not. It is used only when polling_inner 
%                               is "opportunistic". Default: true.
%   permuting_period            It is only used in PBDS, which shuffles the blocks every
%                               permuting_period iterations. A positive integer. Default: 1.   
%   replacement_delay           It is only used for RBDS. Suppose that replacement_delay is r. 
%                               If block i is selected at iteration k, then it will not be 
%                               selected at iterations k+1, ..., k+r. An integer between 0 
%                               and num_blocks-1. Default: 0.
%   seed                        The seed for permuting blocks in PBDS or randomly choosing 
%                               one block in RBDS.
%                               It is only for reproducibility in experiments. A positive integer.
%   output_xhist                Whether to output the history of points visited. Default: false.
%   output_alpha_hist           Whether to output the history of step sizes. Default: false.
%   output_block_hist           Whether to output the history of blocks visited. Default: false.
%   iprint                      a flag deciding whether to print during the computation.
%                               Default: 0, which means no printing. If iprint is 1, then
%                               the function values, the corresponding point, and the step
%                               size will be printed in each function evaluation.
%
%   [XOPT, FOPT] = BDS_OCTAVE(...) returns an approximate minimizer XOPT and its function
%   value FOPT.
%
%   [XOPT, FOPT, EXITFLAG] = BDS_OCTAVE(...) also returns an EXITFLAG that indicates the exit 
%   condition. The possible values of EXITFLAG are 0, 1, 2, and 3.
%
%   0    The StepTolerance of the step size is reached.
%   1    The target of the objective function is reached.
%   2    The maximum number of function evaluations is reached.
%   3    The maximum number of iterations is reached.
%
%   [XOPT, FOPT, EXITFLAG, OUTPUT] = BDS_OCTAVE(...) returns a
%   structure OUTPUT with the following fields.
%
%   fhist        History of function values.
%   xhist        History of points visited (if output_xhist is true).
%   alpha_hist   History of step size for every iteration (if alpha_hist is true).
%   blocks_hist  History of blocks visited (if block_hist is true).
%   funcCount    The number of function evaluations.
%   message      The information of EXITFLAG.
%
%   ***********************************************************************
%   Authors:    Haitian LI (hai-tian.li@connect.polyu.hk)
%               and Zaikun ZHANG (zaikun.zhang@polyu.edu.hk)
%               Department of Applied Mathematics,
%               The Hong Kong Polytechnic University
%   ***********************************************************************
%   All rights reserved.
%

% Set options to an empty structure if it is not provided.
if nargin < 3
    options = struct();
end

% Transpose x0 if it is a row.
x0_is_row = isrow(x0);
x0 = double(x0(:));

% Set the default value of debug_flag. If options do not contain debug_flag, then
% debug_flag is set to false.
if isfield(options, "debug_flag")
    debug_flag = options.debug_flag;
else
    debug_flag = false;
end

% Check the inputs of the user when debug_flag is true.
if debug_flag
    verify_preconditions(fun, x0, options);
end

% If FUN is a string, then convert it to a function handle.
if ischarstr(fun)
    fun = str2func(fun);
end
% Redefine fun to accept columns if x0 is a row, as we use columns internally.
fun_orig = fun;
if x0_is_row
    fun = @(x)fun(x');
end

% To avoid that the users bring some randomized strings.
if ~isfield(options, "seed")
    options.seed = get_default_constant("seed");
end

% The 'RandStream' function is not yet implemented in Octave. So the following line
% does not work in Octave.
% random_stream = RandStream("mt19937ar", "Seed", options.seed);
rand("seed", options.seed);

% Get the dimension of the problem.
n = length(x0);
% Set the default Algorithm of BDS, which is "cbds".
if ~isfield(options, "Algorithm")
    options.Algorithm = get_default_constant("Algorithm");
end

% If there exists the field "direction_set_type" of options, then we will generate the direction
% set according to the value of "direction_set_type".
if isfield(options, "direction_set_type") 
    if strcmpi(options.direction_set_type, "randomized_orthogonal")
        random_matrix = randn(n); 
        [options.direction_set, ~] = qr(random_matrix); 
    elseif strcmpi(options.direction_set_type, "randomized")
        options.direction_set = randn(n); 
    end
end
% Get the direction set.
D = get_direction_set(n, options);

% Get the number of blocks.
num_directions = size(D, 2);
if strcmpi(options.Algorithm, "ds")
    % For ds, num_blocks can only be 1.
    num_blocks = 1;
elseif isfield(options, "block")
    % num_blocks cannot exceed num_directions.
    num_blocks = min(num_directions, options.block);
elseif strcmpi(options.Algorithm, "cbds") || strcmpi(options.Algorithm, "pbds") ...
    || strcmpi(options.Algorithm, "rbds") || strcmpi(options.Algorithm, "pads") ...
    || strcmpi(options.Algorithm, "scbds")
    % For these algorithms, the default value of num_blocks is num_directions/2. 
    num_blocks = ceil(num_directions/2);
end

% Determine the indices of directions in each block.
direction_set_indices = divide_direction_set(n, num_blocks);

% Set the factor for expanding the step sizes.
if isfield(options, "expand")
    expand = options.expand;
else
    expand = get_default_constant("expand");
end

% Set the factor for shrinking the step sizes.
if isfield(options, "shrink")
    shrink = options.shrink;
else
    shrink = get_default_constant("shrink");
end
 
% Set the value of reduction_factor.
if isfield(options, "reduction_factor")
    reduction_factor = options.reduction_factor;
else
    reduction_factor = get_default_constant("reduction_factor");
end

% Set the forcing function, which should be the function handle.
if isfield(options, "forcing_function")
    forcing_function = options.forcing_function;
else
    forcing_function = get_default_constant("forcing_function");
end
% If the forcing function is a string, then convert it to a function handle.
if isfield(options, "forcing_function_type")
    switch options.forcing_function_type
        case "quadratic"
            forcing_function = @(x)x.^2;
        case "cubic"
            forcing_function = @(x)x.^3;
    end
end

% Set polling_inner, which is the polling strategy employed within one block.
if ~isfield(options, "polling_inner")
    options.polling_inner = get_default_constant("polling_inner");
end

% Set cycling_inner, which represents the cycling strategy inside each block.
if isfield(options, "cycling_inner")
    cycling_inner = options.cycling_inner;
else
    cycling_inner = get_default_constant("cycling_inner");
end

% Set permuting_period. This is done only when Algorithm is "pbds", which 
% permutes the blocks every permuting_period iterations.
if strcmpi(options.Algorithm, "pbds") 
    if isfield(options, "permuting_period")
        permuting_period = options.permuting_period;
    else
        permuting_period = get_default_constant("permuting_period");
    end
end

% Set replacement_delay. This is done only when Algorithm is "rbds", which 
% randomly selects a block to visit in each iteration. If replacement_delay is r,
% then the block that is selected in the current iteration will not be selected in
% the next r iterations. Note that replacement_delay cannot exceed num_blocks-1. 
if strcmpi(options.Algorithm, "rbds") 
    if isfield(options, "replacement_delay")
        replacement_delay = min(options.replacement_delay, num_blocks-1);
    else
        replacement_delay = min(get_default_constant("replacement_delay"), num_blocks-1);
    end
end

% Set the boolean value of with_cycling_memory, which will be used in cycling.m.
% cycling.m decides the order of the directions in each block when we perform direct search
% in this block. This order is represented by direction_indices. If with_cycling_memory is true, 
% then direction_indices is decided based on the last direction_indices; otherwise, it is 
% decided based on the initial direction_indices.
if isfield(options, "with_cycling_memory")
    with_cycling_memory = options.with_cycling_memory;
else
    with_cycling_memory = get_default_constant("with_cycling_memory");
end

% Set the maximum number of function evaluations. If the options do not contain MaxFunctionEvaluations,
% it is set to MaxFunctionEvaluations_dim_factor*n, where n is the dimension of the problem.
if isfield(options, "MaxFunctionEvaluations")
    MaxFunctionEvaluations = options.MaxFunctionEvaluations;
else
    MaxFunctionEvaluations = get_default_constant("MaxFunctionEvaluations_dim_factor")*n;
end

% Set the maximum number of iterations. 
% Each iteration will use at least one function evaluation. Setting maxit to MaxFunctionEvaluations will 
% ensure that MaxFunctionEvaluations is exhausted before maxit is reached. 
maxit = MaxFunctionEvaluations; 

% Set the value of StepTolerance. The algorithm will terminate if the stepsize is less than 
% the StepTolerance.
if isfield(options, "StepTolerance")
    alpha_tol = options.StepTolerance;
else
    alpha_tol = get_default_constant("StepTolerance");
end

% Set the target of the objective function.
if isfield(options, "ftarget")
    ftarget = options.ftarget;
else
    ftarget = get_default_constant("ftarget");
end

% Decide whether to output the history of step sizes.
if isfield(options, "output_alpha_hist")
    output_alpha_hist = options.output_alpha_hist;
else
    output_alpha_hist = get_default_constant("output_alpha_hist");
end
% Initialize alpha_hist if output_alpha_hist is true and alpha_hist does not exceed the 
% maximum memory size allowed.
if output_alpha_hist
    try
        alpha_hist = NaN(num_blocks, maxit);
    catch
        output_alpha_hist = false;
        warning("alpha_hist will be not included in the output due to the limit of memory." )
    end
end

% Set the initial step sizes. If options do not contain the field of alpha_init, then the 
% initial step size of each block is set to 1.
if isfield(options, "alpha_init")
    if length(options.alpha_init) == 1
        alpha_all = options.alpha_init*ones(num_blocks, 1);
    elseif length(options.alpha_init) == num_blocks
        alpha_all = options.alpha_init;
    else
        error("The length of alpha_init should be equal to num_blocks or equal to 1.");
    end
elseif (num_blocks == n && size(D, 2) == 2*n && isfield(options, "alpha_init_scaling")) ...
     && options.alpha_init_scaling
    % x0_coordinates is the coordinates of x0 with respect to the directions in 
    % D(:, 1 : 2 : 2*n-1), where D(:, 1 : 2 : 2*n-1) is a basis of R^n.
    x0_coordinates = D(:, 1 : 2 : 2*n-1) \ x0;
    x0_scales = abs(x0_coordinates());
    if isfield(options, "alpha_init_scaling_factor")
        alpha_all = options.alpha_init_scaling_factor * x0_scales;
    else
        alpha_all = 0.5 * max(1, abs(x0_scales));
    end
else
    alpha_all = ones(num_blocks, 1);
end

% fopt_all(i) records the best function values encountered in the i-th block after one iteration, 
% and xopt_all(:, i) is the corresponding value of x.
fopt_all = NaN(1, num_blocks);
xopt_all = NaN(n, num_blocks);

% Initialize the history of function values.
fhist = NaN(1, MaxFunctionEvaluations);

% Initialize the history of points visited.
if isfield(options, "output_xhist")
    output_xhist = options.output_xhist;
else
    output_xhist = get_default_constant("output_xhist");
end
% If xhist exceeds the maximum memory size allowed, then we will not output xhist.
if output_xhist
    try
        xhist = NaN(n, MaxFunctionEvaluations);
    catch
        output_xhist = false;
        warning("xhist will be not included in the output due to the limit of memory.");
    end
end

% Decide whether to output the history of blocks visited.
if isfield(options, "output_block_hist")
    output_block_hist = options.output_block_hist;
else
    output_block_hist = get_default_constant("output_block_hist");
end

% Decide whether to print during the computation.
if isfield(options, "iprint")
    iprint = options.iprint;
else
    iprint = get_default_constant("iprint");
end

% Initialize the history of blocks visited.
block_hist = NaN(1, MaxFunctionEvaluations);

% Initialize exitflag. If exitflag is not set elsewhere, then the maximum number of iterations
% is reached, and hence we initialize exitflag to the corresponding value. 
exitflag = get_exitflag("MAXIT_REACHED", debug_flag);

% Initialize xbase and fbase. xbase serves as the "base point" for the computation in the next 
% block, meaning that reduction will be calculated with respect to xbase. fbase is the function 
% value at xbase.
xbase = x0; 
% fbase_real is the real function value at xbase, which is the value returned by fun 
% (not eval_fun).
[fbase, fbase_real] = eval_fun(fun, xbase);

if iprint == 1
    fprintf("Function number %d, F = %f\n", 1, fbase);
    fprintf("The corresponding X is:\n");
    fprintf("%f  ", xbase(:)');
    fprintf("\n");
end
% Initialize xopt and fopt. xopt is the best point encountered so far, and fopt is the
% corresponding function value. 
xopt = xbase;
fopt = fbase;

% Initialize nf (the number of function evaluations), xhist (history of points visited), and 
% fhist (history of function values).
nf = 1; 
if output_xhist
    xhist(:, nf) = xbase;
end
% When we record fhist, we should use the real function value at xbase, which is fbase_real.
fhist(nf) = fbase_real;

terminate = false;
% Check whether FTARGET is reached by fopt. If it is true, then terminate.
if fopt <= ftarget
    information = "FTARGET_REACHED";
    exitflag = get_exitflag(information);
    
    % FTARGET has been reached at the very first function evaluation. 
    % In this case, no further computation should be entertained, and hence, 
    % no iteration should be run.
    maxit = 0;
end

% If there exists the field "block_indices_permuted_init" of options, and its value is true,
% then we will permute the block_indices at the very beginning.
if isfield(options, "block_indices_permuted_init") && options.block_indices_permuted_init
    all_block_indices = randperm(num_blocks);
else
    all_block_indices = (1:num_blocks);
end
% Initialize the number of blocks visited.
num_visited_blocks = 0;

for iter = 1:maxit

    % Define block_indices, which is a vector containing the indices of blocks that we 
    % are going to visit in this iteration.
    if strcmpi(options.Algorithm, "ds") || strcmpi(options.Algorithm, "cbds") ...
        || strcmpi(options.Algorithm, "pads")
        % If the Algorithm is "ds", "cbds" or "pads", then we will visit all blocks in order.
        % When the Algorithm is "ds", note that num_blocks = 1 and block_indices = [1],
        % a vector of length 1.
        block_indices = all_block_indices;
    elseif strcmpi(options.Algorithm, "pbds") && mod(iter - 1, permuting_period) == 0
        % Starting from the very first iteration, permute the blocks every permuting_period 
        % iterations if the Algorithm is "pbds". Note that block_indices gets initialized 
        % when iter = 1. 
        block_indices = randperm(num_blocks);
    elseif strcmpi(options.Algorithm, "rbds")
        % Get the block that is going to be visited in this iteration when the Algorithm is "rbds".
        % This block should not have been visited in the previous replacement_delay iterations.
        % Note that block_indices is a vector of length 1 in this case. 
        unavailable_block_indices = block_hist(max(1, iter-replacement_delay) : iter - 1);
        available_block_indices = setdiff(all_block_indices, unavailable_block_indices);
        % Select a block randomly from available_block_indices.
        idx = randi(length(available_block_indices));
        block_indices = available_block_indices(idx);  % a vector of length 1
    elseif strcmpi(options.Algorithm, "scbds")
        % Get the block that is going to be visited in this iteration when the Algorithm 
        % is "scbds".
        % In this case, we regard the indices of blocks as a cycle, and we will visit the blocks
        % in the cycle in order. For example, if num_blocks = 3, then the cycle 
        % is [1 2 3 2 1 2 3 2 1 ...]. For implementation, block_indices is a vector of 
        % length 2n-2, where the order of the first n elements is [1 2 3 ... n n-1 ... 2].  
        block_indices = [all_block_indices (num_blocks-1):-1:2];
    end

    for i = 1:length(block_indices)

        % i_real = block_indices(i) is the real index of the block to be visited. For example, 
        % if block_indices is [1 3 2] and i = 2, then we are going to visit the 3rd block.
        i_real = block_indices(i);
        
        % Get indices of directions in the i_real-th block.
        direction_indices = direction_set_indices{i_real}; 
        
        % Set the options for the direct search within the i_real-th block. 
        suboptions.FunctionEvaluations_exhausted = nf;
        suboptions.MaxFunctionEvaluations = MaxFunctionEvaluations - nf;
        suboptions.cycling_inner = cycling_inner;
        suboptions.with_cycling_memory = with_cycling_memory;
        suboptions.reduction_factor = reduction_factor;
        suboptions.forcing_function = forcing_function;
        suboptions.ftarget = ftarget;
        suboptions.polling_inner = options.polling_inner;
        suboptions.iprint = iprint;
        suboptions.debug_flag = debug_flag;
        
        % Perform the direct search within the i_real-th block.
        [sub_xopt, sub_fopt, sub_exitflag, sub_output] = inner_direct_search(fun, xbase,...
            fbase, D(:, direction_indices), direction_indices,...
            alpha_all(i_real), suboptions);

        % Record the index of the block visited.
        num_visited_blocks = num_visited_blocks + 1;     
        block_hist(num_visited_blocks) = i_real;   

        % Record the step size used by inner_direct_search above.
        if output_alpha_hist
            alpha_hist(:, iter) = alpha_all;
        end
        
        % Record the points visited by inner_direct_search if output_xhist is true.
        if output_xhist
            xhist(:, (nf+1):(nf+sub_output.nf)) = sub_output.xhist;
        end

        % Record the function values calculated by inner_direct_search, 
        fhist((nf+1):(nf+sub_output.nf)) = sub_output.fhist;

        % Update the number of function evaluations.
        nf = nf+sub_output.nf;
        
        % Update the step size alpha_all according to the reduction achieved. 
        if sub_fopt + reduction_factor(3) * forcing_function(alpha_all(i_real)) < fbase
            alpha_all(i_real) = expand * alpha_all(i_real);
        elseif sub_fopt + reduction_factor(2) * forcing_function(alpha_all(i_real)) >= fbase
            alpha_all(i_real) = shrink * alpha_all(i_real);
        end
        
        % Record the best function value and point encountered in the i_real-th block.
        fopt_all(i_real) = sub_fopt;
        xopt_all(:, i_real) = sub_xopt;

        % If the Algorithm is not "pads", then we will update xbase and fbase after finishing the
        % direct search in the i_real-th block. For "pads", we will update xbase and fbase after
        % one iteration of the outer loop.
        if ~strcmpi(options.Algorithm, "pads")
            % Update xbase and fbase. xbase serves as the "base point" for the computation in the next block,
            % meaning that reduction will be calculated with respect to xbase, as shown above. 
            % Note that their update requires a sufficient decrease if reduction_factor(1) > 0.
            if (reduction_factor(1) <= 0 && sub_fopt < fbase) ...
                || sub_fopt + reduction_factor(1) * forcing_function(alpha_all(i_real)) < fbase
                xbase = sub_xopt;
                fbase = sub_fopt;
            end
        end
                       
        % Retrieve the direction indices of the i_real-th block, which represent the order of the 
        % directions in the i_real-th block when we perform the direct search in this block next time.
        direction_set_indices{i_real} = sub_output.direction_indices;

        % Terminate the computations if sub_output.terminate is true, which means that inner_direct_search
        % decides that the algorithm should be terminated for some reason indicated by sub_exitflag.
        if sub_output.terminate
            terminate = true;
            exitflag = sub_exitflag;
            break;
        end

        % Terminate the computations if the largest step size is below StepTolerance.
        if max(alpha_all) < alpha_tol
            terminate = true;
            exitflag = get_exitflag("SMALL_ALPHA");
            break;
        end 
    end
    
    % Update xopt and fopt. Note that we do this only if the iteration encounters a strictly better point.
    % Make sure that fopt is always the minimum of fhist after the moment we update fopt.
    % The determination between fopt_all and fopt is to avoid the case that fopt_all is
    % bigger than fopt due to the update of xbase and fbase.
    % In Octave, min does not support "omitnan".
    % [~, index] = min(fopt_all, [], 'omitnan');
    [~, index] = min(fopt_all);
    if fopt_all(index) < fopt
        fopt = fopt_all(index);
        xopt = xopt_all(:, index);
    end
    
    % Test whether fopt is always the minimum of fhist after the moment we update fopt.
    % fopt == min(fhist);

    % For "pads", we will update xbase and fbase only after one iteration of the outer loop.
    % During the inner loop, every block will share the same xbase and fbase.
    if strcmpi(options.Algorithm, "pads")
        % Update xbase and fbase. xbase serves as the "base point" for the computation in the 
        % next block, meaning that reduction will be calculated with respect to xbase, as shown above. 
        % Note that their update requires a sufficient decrease if reduction_factor(1) > 0.
        if (reduction_factor(1) <= 0 && fopt < fbase) || fopt + reduction_factor(1) * forcing_function(min(alpha_all)) < fbase
            xbase = xopt;
            fbase = fopt;
        end
    end

    % Terminate the computations if terminate is true.
    if terminate
        break;
    end
    
end

% Record the number of function evaluations in output.
output.funcCount = nf;

% Truncate the histories of the blocks visited, the step sizes, the points visited, 
% and the function values. 
if output_block_hist
    output.blocks_hist = block_hist(1:num_visited_blocks);
end
if output_alpha_hist
    output.alpha_hist = alpha_hist(:, 1:min(iter, maxit));
end
if output_xhist
    output.xhist = xhist(:, 1:nf);
end
output.fhist = fhist(1:nf);

% Set the message according to exitflag.
switch exitflag
    case {get_exitflag("SMALL_ALPHA", debug_flag)}
        output.message = "The StepTolerance of the step size is reached.";
    case {get_exitflag("MAXFUN_REACHED", debug_flag)}
        output.message = "The maximum number of function evaluations is reached.";
    case {get_exitflag("FTARGET_REACHED", debug_flag)}
        output.message = "The target of the objective function is reached.";
    case {get_exitflag("MAXIT_REACHED", debug_flag)}
        output.message = "The maximum number of iterations is reached.";
    otherwise
        output.message = "Unknown exitflag";
end

% Transpose xopt if x0 is a row.
if x0_is_row
    xopt = xopt';
end

% verify_postconditions is to detect whether the output is valid when debug_flag is true.
if debug_flag
    verify_postconditions(fun_orig, xopt, fopt, exitflag, output);
end
