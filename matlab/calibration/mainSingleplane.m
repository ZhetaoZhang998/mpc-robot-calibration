% 基于平面约束的拉线标定：保留原来的逐点计算、delta累加和参数更新写法。
% 阅读顺序：读取单平面数据 -> 拟合固定点P0 -> 初始化平面 -> 联合标定 -> 输出误差。
% delta2/3用于固定点拟合；delta0/1用于联合更新；delta4检查梯度；delta8更新乘子。
clearvars
close all
tic
%------------------------------------------
%% 一、读取单平面数据及标称DH参数
% 参数顺序：a1~a6，d1~d6，alpha1~alpha6，theta0_1~theta0_6
% 长度单位为m，角度单位为rad。
a_d_alpha_theta0_norm0=...
    [0.24985003 0.90032123 -0.20614449 0 0 0 ...
     0.6535 0 0 1.03037534 0 0.2006 ...
     -1.571 0 1.571 -1.571 1.571 0 ...
     0 0 0 0 0 0]';
a_d_alpha_theta0=a_d_alpha_theta0_norm0;
projectDir=fileparts(mfilename('fullpath'));
dataFile=fullfile(projectDir,'..','..','data','provided_selection','HSR-P_DE_top100.xlsx');
% Optional: use a regenerated workbook by replacing provided_selection with selected above.
assert(isfile(dataFile),'Selected measurement workbook is missing.');% DE筛选后的数据，列顺序和单位与原数据一致
sheetName='HSR-P1';% 单平面选择；可改为HSR-P2或HSR-P3
dataRange='A2:H101';% 跳过表头，读取该平面筛选后的100组数据
data=readmatrix(dataFile,'Sheet',sheetName,'Range',dataRange);
% Sheet选择平面，Range选择Excel源行；本程序将选中范围全部用于训练，没有独立测试集。
% isfinite仅检查NaN/Inf，不能识别测量离群值，百分表读数仍需结合原始记录核对。
assert(size(data,2)==8 && all(isfinite(data(:))),'测量数据必须包含8列有效数值。');
q1_batch=pi/180*data(:,1);
% 第1~6列为关节角（度转rad）；第7列为拉线长度，第8列为百分表读数（mm转m）。
q2_batch=pi/180*data(:,2);
q3_batch=pi/180*data(:,3);
q4_batch=pi/180*data(:,4);
q5_batch=pi/180*data(:,5);
q6_batch=pi/180*data(:,6);
L_ex11=data(:,7)/1000;
K=data(:,8)/1000;% 百分表读数
N=length(q1_batch);

%------------------------------------------
%% 二、先用标称机器人参数拟合拉线固定点P0
% 此阶段仅调整固定点xyz，24个DH参数保持不变；得到的P0在后续标定中固定。
% 拟合目标：mean((norm(Pos_i-P0)-L_ex_i)^2)/2。
Pos_batch=zeros(N,3);
Axis_batch=zeros(N,3);
for i=1:N
    q=[q1_batch(i);q2_batch(i);q3_batch(i);q4_batch(i);q5_batch(i);q6_batch(i)];
    [Pos_norm1,J_norm4]=my_forward_main2(a_d_alpha_theta0,q);
    Pos_batch(i,:)=Pos_norm1';
    Axis_batch(i,:)=J_norm4(:,12)';% d6方向，用于计算探针接触点
end
xyz=[2 1.5 0.05];
% xyz是固定点初值；KH0是固定点拟合的阻尼，不是DH参数的正则系数。
KH0=0.002;
MSE_store1=zeros(100,1);
for iteration=1:100
    delta2=zeros(3,1);
    delta3=zeros(3,3);
    MSE1=0;
    for i=1:N
        L_norm0=norm(Pos_batch(i,:)-xyz);
        J_norm0=(xyz-Pos_batch(i,:))/max(L_norm0,eps);
        % 对P0求导为(P0-Pos)/距离，符号与对末端位置求导相反。
        Error=L_norm0-L_ex11(i);
        delta2=delta2+J_norm0'*Error;
        % delta2累加梯度，delta3累加正半定的Gauss-Newton近似Hessian。
        delta3=delta3+J_norm0'*J_norm0;
        MSE1=MSE1+Error^2;
    end
    delta2=delta2/N;
    delta3=delta3/N;
    MSE1=MSE1/N;
    MSE_store1(iteration)=MSE1;
    accepted=false;
    for trial=1:12% 更新后误差变大，就增大阻尼重新计算
        % 先试算，再比较真实拉线平方误差；误差下降才接受这一步。
        step=-(delta3+KH0*eye(3))\delta2;
        xyz_try=xyz+step';
        MSE_try=0;
        for i=1:N
            Error=norm(Pos_batch(i,:)-xyz_try)-L_ex11(i);
            MSE_try=MSE_try+Error^2;
        end
        if MSE_try/N<MSE1
            xyz=xyz_try;
            KH0=max(KH0/3,1e-12);
            accepted=true;
            break
        end
        KH0=KH0*10;
    end
    if ~accepted || norm(step)<1e-10
        break
    end
end
MSE_store1=MSE_store1(1:iteration);
% MSE_store1保存固定点拟合的均方误差，单位m^2；不是下面画图用的RMSE。
P0=xyz;% 拉线固定点，后续保持固定

%------------------------------------------
%% 三、初始化单平面及优化参数
% 机器人参数、L和平面参数在同一轮联合更新，随后再更新z和T1。
L=0.22039;
L0=L;
% L为百分表本体长度，K为读数；补偿L-K沿实际装配的d6方向作用于接触点。
Pos_plane=Pos_batch+(L-K).*Axis_batch;
center=mean(Pos_plane,1);
[~,~,V]=svd(Pos_plane-center,0);
% 点云中心化后，最小奇异值对应方向作为初始法向量。
beta0=V(:,end)';% 单位平面法向量
if beta0(3)<0
    beta0=-beta0;
end
planeOffset=center*beta0';% 平面方程：Pos'*beta0'-planeOffset=0
x0=planeOffset*beta0;% 平面上的点，不对x0做归一化
% 单位法向量满足norm(beta0)=1；平面方程为Pos'*beta0'-planeOffset=0。
% x0取平面上离原点最近的点，其长度没有必须等于1的要求。

PH1=1;% ADMM惩罚系数
% PH1控制增广惩罚；planeWeight控制平面残差在最终实际目标中的权重。
% KH1、KH2抑制参数偏离标称值；KH5是每次求解的阻尼，作用不同。
planeWeight=1;% 平面测量残差的权重
KH1=0.0001;% DH参数偏离标称值的正则系数，抑制参数漂移
KH2=0.0001;% L偏离初始值的正则系数
KH5=0.0001;% 迭代阻尼，误差增大时自动增大
Iter=300;
T1=zeros(N,1);% 每个测量点对应一个乘子
z=zeros(N,1);% 平面测量中的噪声残差，不强迫所有测量误差精确为零
J_prior=diag([KH1*ones(1,24),KH2,0,0,0]);
% 联合增量共28维：1:24为DH，25为L，26:27为法向量切向修正，28为平面偏置。
% J_prior只对DH和L施加标称正则，不把平面位置固定到某个标称值。
MSE_store=zeros(Iter+1,1);
% MSE_store沿用旧变量名，实际保存拉线RMSE；MSE_store0保存平面RMSE，单位均为m。
% 历史数组第1项为参数更新前的初始结果，对应图中的Iteration=0。
MSE_store0=zeros(Iter+1,1);
objective_store=zeros(Iter+1,1);
primal_store=zeros(Iter,1);
dual_store=zeros(Iter,1);
Error_store=sqrt(sum((Pos_batch-P0).^2,2))-L_ex11;
Error0_store=Pos_plane*beta0'-planeOffset;
MSE_store(1)=sqrt(mean(Error_store.^2));
MSE_store0(1)=sqrt(mean(Error0_store.^2));
objective_store(1)=mean(Error_store.^2+planeWeight*Error0_store.^2)/2;
converged=false;
gradientTolerance=1e-9;

%% 四、联合更新28维原变量：逐点累加梯度和近似Hessian
% 实际目标F = mean(e^2+planeWeight*c^2)/2
%             + KH1*norm(DH-DH标称)^2/2 + KH2*(L-L0)^2/2。
% e为拉线距离残差；c为接触点到平面的有符号距离；ADMM将带噪约束写成c=z。
% 每轮先固定z、T1进行内层参数修正，再用新参数更新z、T1。
for iteration=1:Iter
    parameters_old=[a_d_alpha_theta0;L;beta0';planeOffset];
    u=T1/PH1;
    % u为缩放后的对偶变量；T1和z都是N×1，分别对应每个测量点。
    for inner=1:8% 先修正参数，再更新乘子T1
        delta0=zeros(28,1);
        delta1=zeros(28,28);
        MSE=0;
        MSE0=0;
        B=null(beta0);% B的两列为垂直于法向量的方向，用于保持法向量长度为1
        for i=1:N
            q=[q1_batch(i);q2_batch(i);q3_batch(i);q4_batch(i);q5_batch(i);q6_batch(i)];
            % 拉线距离残差及其对机器人参数的导数
            [Pos_norm1,J_norm4]=my_forward_main2(a_d_alpha_theta0,q);
            L_norm1=norm(Pos_norm1-P0');
            J_norm1=[(Pos_norm1'-P0)/max(L_norm1,eps)*J_norm4,zeros(1,4)];
            % 距离对位置的导数乘位置雅可比；末尾4个零表示不依赖L和平面参数。
            Error=L_norm1-L_ex11(i);
            % 接触点：只把第12个DH参数d6增加L-K(i)
            MM=zeros(24,1);
            MM(12)=L-K(i);
            % 补偿只用于接触点模型；拉线距离仍由未附加该补偿的DH模型计算。
            X=a_d_alpha_theta0+MM;
            [Pos_norm0,J_norm4]=my_forward_main2(X,q);
            Error0=Pos_norm0'*beta0'-planeOffset;
            % 联合修正量顺序：24个DH参数、L、法向量的2个方向、平面偏置
            J_norm0=[beta0*J_norm4,beta0*J_norm4(:,12),Pos_norm0'*B,-1];
            % 分块对应DH、L、法向量切向2维、平面偏置；L使用d6列求导。
            Error1=Error0-z(i)+u(i);
            % Error0是真实平面距离c，Error1是增广子问题中的偏移残差。
            % delta0/1同时保留拉线、平面以及参数之间的交叉信息。
            delta0=delta0+J_norm1'*Error+PH1*J_norm0'*Error1;
            delta1=delta1+J_norm1'*J_norm1+PH1*(J_norm0'*J_norm0);
            MSE=MSE+Error^2;
            MSE0=MSE0+Error1^2;
        end
        delta_prior=[a_d_alpha_theta0-a_d_alpha_theta0_norm0;L-L0;zeros(3,1)];
        delta0=delta0/N+J_prior*delta_prior;
        % 样本累加后取平均，正则项只加一次；不要在每个样本中重复施加正则。
        delta1=delta1/N+J_prior;
        Cost=(MSE+PH1*MSE0)/(2*N)+delta_prior'*J_prior*delta_prior/2;

        % 集中更新参数；只有增广子问题总目标下降时才接受这一步。
        % 该条件不保证单独的拉线RMSE下降，异常平面数据可能牺牲拉线拟合精度。
        accepted=false;
        for trial=1:12
            step=-(delta1+KH5*eye(28))\delta0;
            % 求解阻尼方程得到参数增量，避免直接计算矩阵逆。
            step=step/max(1,max(abs(step))/0.02);% 限制每次参数改变量
            a_d_alpha_theta0_try=a_d_alpha_theta0+step(1:24);
            L_try=L+step(25);
            beta0_try=beta0+(B*step(26:27))';
            % 先沿垂直于法向量的两个方向修正，再归一化，维持单位法向量约束。
            beta0_try=beta0_try/norm(beta0_try);
            planeOffset_try=planeOffset+step(28);
            MSE_try=0;
            MSE0_try=0;
            for i=1:N
                q=[q1_batch(i);q2_batch(i);q3_batch(i);q4_batch(i);q5_batch(i);q6_batch(i)];
                Pos_norm1=my_forward_main2(a_d_alpha_theta0_try,q);
                Error=norm(Pos_norm1-P0')-L_ex11(i);
                MM=zeros(24,1);
                MM(12)=L_try-K(i);
                Pos_norm0=my_forward_main2(a_d_alpha_theta0_try+MM,q);
                Error0=Pos_norm0'*beta0_try'-planeOffset_try;
                MSE_try=MSE_try+Error^2;
                MSE0_try=MSE0_try+(Error0-z(i)+u(i))^2;
            end
            delta_prior_try=[a_d_alpha_theta0_try-a_d_alpha_theta0_norm0;L_try-L0;zeros(3,1)];
            Cost_try=(MSE_try+PH1*MSE0_try)/(2*N)+delta_prior_try'*J_prior*delta_prior_try/2;
            if L_try>0 && isfinite(Cost_try) && Cost_try<Cost
                a_d_alpha_theta0=a_d_alpha_theta0_try;
                L=L_try;
                beta0=beta0_try;
                planeOffset=planeOffset_try;
                KH5=max(KH5/3,1e-10);
                accepted=true;
                break
            end
            KH5=min(KH5*10,1e8);
        end
        if ~accepted || norm(step)<1e-9
            break
        end
    end
    x0=planeOffset*beta0;

    % 【五】用新参数重新计算残差，再更新噪声变量z和对偶变量T1。
    % delta4计算实际目标F的梯度，用于驻点判断，不叠加旧的增广偏移项。
    delta4=zeros(28,1);
    B=null(beta0);
    for i=1:N
        q=[q1_batch(i);q2_batch(i);q3_batch(i);q4_batch(i);q5_batch(i);q6_batch(i)];
        [Pos_norm1,J_norm4]=my_forward_main2(a_d_alpha_theta0,q);
        L_norm1=norm(Pos_norm1-P0');
        J_norm1=[(Pos_norm1'-P0)/max(L_norm1,eps)*J_norm4,zeros(1,4)];
        MM=zeros(24,1);
        MM(12)=L-K(i);
        [Pos_norm0,J_norm4]=my_forward_main2(a_d_alpha_theta0+MM,q);
        J_norm0=[beta0*J_norm4,beta0*J_norm4(:,12),Pos_norm0'*B,-1];
        Error_store(i)=L_norm1-L_ex11(i);
        Error0_store(i)=Pos_norm0'*beta0'-planeOffset;
        delta4=delta4+J_norm1'*Error_store(i)+planeWeight*J_norm0'*Error0_store(i);
    end
    z_old=z;
    % z允许保留测量噪声，下面是平方平面误差对应的近端更新。
    % T1是逐点乘子，采用对偶上升更新；它不和DH参数一起做最小化。
    z=PH1/(PH1+planeWeight)*(Error0_store+u);
    delta8=PH1*(Error0_store-z);
    T1=T1+delta8;
    delta_prior=[a_d_alpha_theta0-a_d_alpha_theta0_norm0;L-L0;zeros(3,1)];
    stationarityNorm=norm(delta4/N+J_prior*delta_prior,inf);
    MSE_store(iteration+1)=sqrt(mean(Error_store.^2));
    MSE_store0(iteration+1)=sqrt(mean(Error0_store.^2));
    objective_store(iteration+1)=mean(Error_store.^2+planeWeight*Error0_store.^2)/2+...
        delta_prior'*J_prior*delta_prior/2;
    primal_store(iteration)=sqrt(mean((Error0_store-z).^2));
    % 原始残差=c-z；对偶残差=PH1*(z-z_old)，均按全部样本计算RMS。
    dual_store(iteration)=PH1*sqrt(mean((z-z_old).^2));

    % 同时检查约束残差、目标变化、参数变化和梯度，避免误判收敛。
    % converged仅代表数值条件满足；是否得到有效标定，还需看精度及数据质量。
    primalTolerance=1e-8+1e-4*max(sqrt(mean(Error0_store.^2)),sqrt(mean(z.^2)));
    dualTolerance=1e-8+1e-4*sqrt(mean(T1.^2));
    parameterChange=norm([a_d_alpha_theta0;L;beta0';planeOffset]-parameters_old,inf);
    objectiveChange=abs(objective_store(iteration+1)-objective_store(iteration))/...
        max(objective_store(iteration),eps);
    if iteration==1 || mod(iteration,10)==0
        fprintf('Iteration %d: cable RMSE=%.6g m, plane RMSE=%.6g m\n',...
            iteration,MSE_store(iteration+1),MSE_store0(iteration+1));
    end
    if iteration>=10 && primal_store(iteration)<=primalTolerance && ...
            dual_store(iteration)<=dualTolerance && objectiveChange<1e-6 && ...
            parameterChange<1e-6 && stationarityNorm<gradientTolerance
        converged=true;
        break
    end
end
MSE_store=MSE_store(1:iteration+1);
MSE_store0=MSE_store0(1:iteration+1);
objective_store=objective_store(1:iteration+1);
primal_store=primal_store(1:iteration);
dual_store=dual_store(1:iteration);
toc

%------------------------------------------
%% 六、绘图及输出：此处曲线和最终指标均为训练数据结果
% 红色曲线画的是拉线训练RMSE，不是平面RMSE，也不是总目标F。
% objective_store保存实际总目标，可用于解释“总目标下降但拉线误差上升”。
format long
figure(1),clf(1)
semilogy(0:iteration,MSE_store,'rx-')
xlabel('Iteration');
ylabel('RMSE (m)');
grid on
disp('Calibrated Parameters:'); disp(a_d_alpha_theta0);
disp('P0 ='); disp(P0);
disp('x0 ='); disp(x0);
disp('beta0 ='); disp(beta0);
disp('L ='); disp(L);
fprintf('Iterations: %d, converged: %d\n',iteration,converged);
if ~converged
    fprintf('Iteration limit reached; inspect the residuals before declaring convergence.\n');
end

% 最后输出拉线距离误差，单位为m。
% MAX是最大绝对误差，MEAN是平均绝对误差。
% RMSE=sqrt(mean(e.^2))；MAX=max(abs(e))；MEAN=mean(abs(e))，e为最后的拉线残差。
% 本文件没有划分测试集；与main3比较时需统一数据范围及评价样本。
RMSE=sqrt(mean(Error_store.^2));
MAX=max(abs(Error_store));
MEAN=mean(abs(Error_store));
fprintf('\nFinal cable training errors (m):\n');
fprintf('RMSE = %.9f m\n',RMSE);
fprintf('MAX  = %.9f m\n',MAX);
fprintf('MEAN = %.9f m\n',MEAN);
