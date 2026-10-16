% DE 三平面测量位姿选择：每个平面独立选取 100 条互不重复的样本。
% 输出同一个 HSR-P_DE_top100.xlsx，分别存入 HSR-P1、HSR-P2、HSR-P3。
clearvars
rng(1); % Fixed seed for this repository.
tic

%% 1. 机器人名义参数和输入、输出设置
% 参数顺序：a(1:6)、d(1:6)、alpha(1:6)、theta0(1:6)。
a_d_alpha_theta0_norm0 = ...
    [0.24872627 0.90065082 -0.20466089 0 0 0 ...
     0.6535 0 0 1.03138548 0 0.2006 ...
     -1.571 0 1.571 -1.571 1.571 0 ...
     0 0 0 0 0 0]';
a_d_alpha_theta0 = a_d_alpha_theta0_norm0;
xyz = [1.68012911207520 -0.157997954177532 0.758930011356163];
script_dir = fileparts(mfilename('fullpath'));
data_file = fullfile(script_dir, '..','..','data','raw','HSR-P.xlsx');
export_dir=fullfile(script_dir,'..','..','data','selected');
if ~isfolder(export_dir), mkdir(export_dir); end
export_file = fullfile(export_dir, 'HSR-P_DE_top100.xlsx');
source_sheets = sheetnames(data_file);
plane_ids = 1:3;                    % 【关键】分别处理三个平面，不混合候选样本。
num_planes = numel(plane_ids);
assert(numel(source_sheets) >= max(plane_ids), 'HSR-P.xlsx 必须包含三个平面工作表。');
data_range = 'A201:H400';             % 每个平面沿用当前设置：200 条候选样本。
num_params = 17;                   % 沿用原 O6：使用雅可比矩阵前 17 列。
% 默认沿用当前固定点 xyz；如果各平面的固定点不同，可逐行填写对应坐标。
xyz_by_plane = repmat(xyz, num_planes, 1);

%% 2. 三个平面共用的 DE 参数，各平面独立初始化和搜索
de.m = 100;                        % 每个平面输出 100 条，总计 300 条数据。
de.Np = 50;                        % 种群大小，DE/rand/1 要求至少为 4。
de.F0 = 0.38;                      % 自适应缩放因子的基准值。
de.CR = 0.75;                      % 二项交叉概率。
de.Iter = 150;                     % 每个平面的迭代代数。
assert(de.Np >= 4, 'DE/rand/1 要求种群大小 Np >= 4。');
assert(de.m >= num_params, '测量数量应不少于待辨识参数数量。');

%% 3. 逐平面优化，并向同一个临时工作簿写入三个工作表
plane_results = struct([]);        % 保存三个平面的索引、适应度及收敛记录。
temp_export = [tempname(export_dir) '.xlsx'];
try
    for plane_idx = 1:num_planes
        sheet_id = plane_ids(plane_idx);
        sheet_name = char(source_sheets(sheet_id));
        data = readmatrix(data_file, 'Sheet', sheet_id, 'Range', data_range);
        if size(data, 2) ~= 8 || isempty(data) || ...
                any(any(~isfinite(data(:, 1:6))))
            error('mainO60:InvalidData', ...
                '%s 必须包含 A:H 八列，且前六列关节角为非空、有限数值。', sheet_name);
        end
        if size(data, 1) < de.m
            error('mainO60:InsufficientSamples', ...
                '%s 候选样本不足 %d 条。', sheet_name, de.m);
        end
        fprintf('\n===== %s：独立选择 %d / %d 条样本 =====\n', ...
            sheet_name, de.m, size(data, 1));

        % 【关键】每个平面使用自己的 data、雅可比缓存和 DE 种群。
        result = optimize_plane_de(data, a_d_alpha_theta0, ...
            xyz_by_plane(plane_idx, :), num_params, de, sheet_name);
        result.sheet_id = sheet_id;
        result.data_range = data_range;
        if plane_idx == 1
            plane_results = result; % 由第一个结果定义结构体字段。
        else
            plane_results(plane_idx) = result;
        end

        % 导出原始 data，保留角度制、L/D 原单位和 q1...q6、L、D 八列表头。
        headers = readcell(data_file, 'Sheet', sheet_id, 'Range', 'A1:H1');
        export_cells = [headers; num2cell(result.selected_data)];
        % 【关键】同一工作簿逐表写入；不能在循环中重建或替换整个输出文件。
        writecell(export_cells, temp_export, 'Sheet', sheet_name, 'Range', 'A1');
        fprintf('%s：最优 O6 = %.12g，已写入 %d 条不同样本。\n', ...
            sheet_name, result.bestO6, size(result.selected_data, 1));
    end

    % 三个平面全部成功后再替换正式输出，避免只留下部分平面的结果。
    [export_ok, export_message] = movefile(temp_export, export_file, 'f');
    if ~export_ok
        error('mainO60:ExportFailed', '%s', export_message);
    end
catch export_error
    if isfile(temp_export)
        delete(temp_export);
    end
    rethrow(export_error);
end
toc
fprintf('\n已导出 %d 个平面，每个平面 %d 条，共 %d 条：\n%s\n', ...
    num_planes, de.m, num_planes * de.m, export_file);
% 工作区访问示例：plane_results(1).best 为第一平面的 data 行号。
% plane_results(2).selected_data 为第二平面导出的原始数据。

%% 4. 三个平面的 -O6 收敛曲线分别显示，最优值随迭代不增
save(fullfile(export_dir,'selection_provenance.mat'),'plane_results','de','data_range','xyz_by_plane','a_d_alpha_theta0');
figure(1), clf(1)
tiledlayout(num_planes, 1, 'TileSpacing', 'compact');
for plane_idx = 1:num_planes
    nexttile
    plot(0:de.Iter, plane_results(plane_idx).trace, 'rx-', 'LineWidth', 1.2);
    xlabel('Iteration');
    ylabel('-O6');
    title(sprintf('%s: DE convergence (-O6)', plane_results(plane_idx).sheet_name));
    grid on
end

%% 局部函数：单个平面的 DE 搜索
function result = optimize_plane_de(data, parameters, xyz, num_params, de, sheet_name)
q0 = pi/180 * data(:, 1:6);
num_candidates = size(q0, 1);
D = de.m;                         % 个体维数等于每个平面选取的位姿数。

% 固定机器人参数和 xyz 后，各候选位姿的雅可比只需计算一次。
J_cache = cell(num_candidates, 1);
for i = 1:num_candidates
    J_norm = my_Jacobian(parameters, xyz, q0(i, :));
    J0 = J_norm(:, 1:num_params);
    if ~isreal(J0) || any(~isfinite(J0(:)))
        error('mainO60:InvalidJacobian', ...
            '%s 的候选位姿 %d 包含无效雅可比数值。', sheet_name, i);
    end
    J_cache{i} = J0;
end

% 【关键】无放回初始化，并将同一组行号按升序统一表示。
X = zeros(D, de.Np);
for k = 1:de.Np
    X(:, k) = sort(randperm(num_candidates, D))';
end
v = zeros(D, de.Np);
u = zeros(D, de.Np);
fitness = zeros(de.Np, 1);
for k = 1:de.Np
    fitness(k) = de_o6_fitness(X(:, k), J_cache, num_params);
end
trace = zeros(de.Iter + 1, 1);
trace(1) = min(fitness);

for t = 1:de.Iter
    lamda = exp(1 - de.Iter/(de.Iter + 1 - t));
    F = de.F0 * 2^lamda;           % 自适应缩放因子，沿用参考 DE 代码。
    for k = 1:de.Np
        % DE/rand/1：三个供体互不相同，且均不等于当前目标个体 k。
        candidates = [1:k-1 k+1:de.Np];
        r = candidates(randperm(de.Np - 1, 3));
        v(:, k) = X(:, r(1)) + F * (X(:, r(2)) - X(:, r(3)));
        v(:, k) = max(1, min(num_candidates, round(v(:, k))));

        % 二项交叉：jrand 在 1:D 中选取，强制至少一个分量来自变异个体。
        cross_mask = rand(D, 1) <= de.CR;
        cross_mask(randi(D)) = true;
        u(:, k) = X(:, k);
        u(cross_mask, k) = v(cross_mask, k);
        % 【关键】交叉后再次去重、无放回补足，保证每组恰好 100 条不同样本。
        u(:, k) = repair_pose_indices(u(:, k), num_candidates);
    end
    for k = 1:de.Np
        trial_fitness = de_o6_fitness(u(:, k), J_cache, num_params);
        if trial_fitness <= fitness(k)  % 一对一贪婪选择，最小化 -O6。
            X(:, k) = u(:, k);
            fitness(k) = trial_fitness;
        end
    end
    trace(t + 1) = min(fitness);
    if t == 1 || mod(t, 10) == 0 || t == de.Iter
        fprintf('%s DE: %3d/%3d, best O6 = %.10g\n', ...
            sheet_name, t, de.Iter, -trace(t + 1));
    end
end

% 一个适应度对应整组 100 个位姿；按整组 -O6 升序选出本次搜索最佳组。
[sorted_fitness, population_order] = sort(fitness, 'ascend');
best = X(:, population_order(1));
result.sheet_name = sheet_name;
result.best = best;                % 对应本平面 data 行号；原始 Excel 行号为 best + 200（当前 A201:H400 窗口）。
result.best_q = q0(best, :);        % 优化计算所用弧度制位姿。
result.selected_data = data(best, :); % 输出使用原始角度制及原始 L、D 数值。
result.bestO6 = -sorted_fitness(1);
result.trace = trace;              % 保存 -O6，直接用于下降趋势图。
result.sorted_fitness = sorted_fitness;
result.population_order = population_order;
result.inx = X';                   % 各行是该平面的一个最终候选组。
result.num_candidates = num_candidates;
end

function indices = repair_pose_indices(indices, num_candidates)
indices = max(1, min(num_candidates, round(indices(:))));
[~, keep_positions] = unique(indices, 'stable');
replace_positions = setdiff((1:numel(indices))', keep_positions);
if ~isempty(replace_positions)
    available = setdiff((1:num_candidates)', indices(keep_positions));
    fill_positions = randperm(numel(available), numel(replace_positions));
    indices(replace_positions) = available(fill_positions);
end
indices = sort(indices);
end

function fitness = de_o6_fitness(indices, J_cache, num_params)
% 沿用原 O6 定义：O6 = sqrt(17)/sqrt(sum(1./sigma.^2))，适应度为 -O6。
% 若原雅可比列存在相关性，O6 仍可能接近零，需注意数值精度的影响。
J_store = vertcat(J_cache{indices});
sigma = svd(J_store, 0);
if numel(sigma) < num_params || sigma(end) <= 0
    fitness = 0;
    return
end
fitness = -sqrt(num_params) * sigma(end) / norm(sigma(end) ./ sigma);
end
