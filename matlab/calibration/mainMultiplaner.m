% 三平面联合标定：主程序汇总三个平面的delta，再更新同一组机器人参数。
% 多平面结构对应论文式(14)~(17)，求解器沿用main2中的含噪ADMM和阻尼更新。
% 阅读顺序：选数据 -> 分别拟合P0 -> 初始化平面 -> 联合更新参数 -> 更新T1 -> 评价。
% 单位：Excel关节角为度、长度为mm；进入运动学模型后统一使用rad和m。
clearvars
close all
tic
%------------------------------------------
%% 一、数据与算法设置：通常只需修改这一部分
% dataRange是候选范围；sampleCount是抽样上限，不一定使用范围内全部数据。
% PH1控制ADMM约束惩罚；planeWeight控制平面误差在最终目标中的权重。
% KH1、KH2限制参数偏离标称值；KH5是单次求解的阻尼，二者作用不同。
projectDir=fileparts(mfilename('fullpath'));
dataFile=fullfile(projectDir,'..','..','data','provided_selection','HSR-P_DE_top100.xlsx');
% Optional: use a regenerated workbook by replacing provided_selection with selected above.
assert(isfile(dataFile),'Selected measurement workbook is missing.');% DE筛选后的数据，每个平面100组，保留原8列及单位
sheetList={'HSR-P1','HSR-P2','HSR-P3'};
dataRange='A2:H101';% 第1行为表头，第2~101行为100组测量数据
sampleCount=100;% 每个平面使用筛选后的100组数据，再按trainRatio划分
trainRatio=0.8;% 每个平面80%训练、20%独立测试；设为1则全部用于训练
randomSeed=1;% 固定随机种子，保证抽样和训练/测试划分可以复现
Iter=300;
PH1=1;% ADMM惩罚系数
planeWeight=1;% 平面测量残差权重
KH1=0.0001;% DH参数标称正则
KH2=0.0001;% 百分表长度L的标称正则
KH5=0.0001;% 自适应迭代阻尼
gradientTolerance=1e-9;

%% 二、读取数据并固定训练/测试划分
% 参数顺序：[a1~a6,d1~d6,alpha1~alpha6,theta0_1~theta0_6]。
a_d_alpha_theta0_norm0=...
    [0.24985003 0.90032123 -0.20614449 0 0 0 ...
     0.6535 0 0 1.03037534 0 0.2006 ...
     -1.571 0 1.571 -1.571 1.571 0 ...
     0 0 0 0 0 0]';
a_d_alpha_theta0=a_d_alpha_theta0_norm0;
projectDir=fileparts(mfilename('fullpath'));
nPlane=length(sheetList);
assert(trainRatio>0 && trainRatio<=1,'trainRatio必须在(0,1]内。');
assert(sampleCount>=4 && (isinf(sampleCount) || sampleCount==floor(sampleCount)),...
    'sampleCount必须为不小于4的整数，或inf。');
assert(PH1>0 && planeWeight>0,'PH1和planeWeight必须为正数。');
rng(randomSeed);
% data{k}、data_test{k}为第k个平面的训练/测试数据，保持原8列配对关系。
% trainRows/testRows保留当前输入Excel的行号，便于回查；测试集不参与更新。
data=cell(nPlane,1);
data_test=cell(nPlane,1);
trainRows=cell(nPlane,1);
testRows=cell(nPlane,1);
N=zeros(nPlane,1);
selectedCount=zeros(nPlane,1);
suspectRows=cell(nPlane,1);% 保存统计上离群的百分表读数所在Excel行，仅提示、不自动剔除
for k=1:nPlane
    data_all=readmatrix(dataFile,'Sheet',sheetList{k},'Range',dataRange);
    assert(size(data_all,2)==8 && all(isfinite(data_all(:))),...
        '每个平面的选定范围必须是8列完整数值。');
    firstRow=sscanf(dataRange,'A%d');
    % 有限数值也可能是录入错误：用中位数和MAD提示特别离群的百分表读数。
    % 这里只提示离群值，不推断正确读数，也不自动删除测量行。
    dial=data_all(:,8);% 原始单位mm
    dialMedian=median(dial);
    dialScale=max(1.4826*median(abs(dial-dialMedian)),0.001);
    suspect=find(abs(dial-dialMedian)>8*dialScale);
    suspectRows{k}=suspect+firstRow-1;
    for j=1:length(suspect)
        warning('main3:DialOutlier',...
            '%s Excel row %d: dial=%.6g mm, median=%.6g mm. Check original measurement; row retained.',...
            sheetList{k},suspectRows{k}(j),dial(suspect(j)),dialMedian);
    end
    M=min(sampleCount,size(data_all,1));
    selectedCount(k)=M;
    selected=randperm(size(data_all,1),M);
    % 先随机抽样，再按比例划分；排序只恢复源行顺序，不改变测量配对。
    N(k)=floor(trainRatio*M);
    assert(N(k)>=3,'每个平面至少需要3组训练数据。');
    trainIndex=sort(selected(1:N(k)));
    testIndex=sort(selected(N(k)+1:end));
    data{k}=data_all(trainIndex,:);
    data_test{k}=data_all(testIndex,:);
    trainRows{k}=trainIndex+firstRow-1;
    testRows{k}=testIndex+firstRow-1;
    fprintf('%s: available %d, selected %d, training %d, test %d\n',...
        sheetList{k},size(data_all,1),M,N(k),size(data_test{k},1));
end
N_total=sum(N);

%------------------------------------------
%% 三、分别拟合固定点，并初始化各自的平面
% 三个平面共享：24个DH参数、百分表长度L。
% 实验中移动过拉线固定点，因此每个平面单独拟合P0(k,:)并保持固定。
% 各平面还分别保存beta0(k,:)、x0(k,:)、planeOffset(k)、T1{k}、z{k}。
P0=zeros(nPlane,3);
MSE_store1=cell(nPlane,1);
for k=1:nPlane
    [P0(k,:),MSE_store1{k}]=my_fit_anchor(a_d_alpha_theta0,data{k});
    % 此处只拟合第k个固定点，DH参数保持不变；不是分别训练三组机器人参数。
end
L=0.22039;
L0=L;
beta0=zeros(nPlane,3);
planeOffset=zeros(nPlane,1);
x0=zeros(nPlane,3);
T1=cell(nPlane,1);
z=cell(nPlane,1);
index=cell(nPlane,1);
% 注意：MSE_store沿用旧名称，实际保存拉线RMSE；MSE_store0保存平面RMSE。
% 历史数组第1行是更新前的初始值，对应图中的Iteration=0。
MSE_store=zeros(Iter+1,1);
MSE_store0=zeros(Iter+1,1);
cable_plane_store=zeros(Iter+1,nPlane);
plane_store=zeros(Iter+1,nPlane);
objective_store=zeros(Iter+1,1);
primal_store=zeros(Iter,1);
dual_store=zeros(Iter,1);
Error_store=cell(nPlane,1);
Error0_store=cell(nPlane,1);
for k=1:nPlane
    Pos_plane=zeros(N(k),3);
    for i=1:N(k)
        q=pi/180*data{k}(i,1:6)';
        MM=zeros(24,1);
        MM(12)=L-data{k}(i,8)/1000;% 百分表补偿沿d6，按实际安装方向设置
        Pos_plane(i,:)=my_forward_main2(a_d_alpha_theta0+MM,q)';
    end
    center=mean(Pos_plane,1);
    [~,~,V]=svd(Pos_plane-center,0);
    % 中心化点云的最小奇异值对应方向，作为这个平面的初始法向量。
    beta0(k,:)=V(:,end)';
    [~,direction]=max(abs(beta0(k,:)));
    if beta0(k,direction)<0
        beta0(k,:)=-beta0(k,:);
    end
    planeOffset(k)=center*beta0(k,:)';
    % 平面方程：Pos'*beta0(k,:)'-planeOffset(k)=0，且法向量长度为1。
    % x0取平面上离原点最近的点；x0的长度不应强制归一化。
    x0(k,:)=planeOffset(k)*beta0(k,:);
    T1{k}=zeros(N(k),1);
    z{k}=zeros(N(k),1);
    % 每个平面的局部28维，映射到共同参数和自己的3个平面参数。
    % 局部1:24=DH，25=L，26:27=法向量切向修正，28=平面偏置修正。
    % 全局1:25共享；26:28属于平面1，29:31属于平面2，32:34属于平面3。
    index{k}=[1:25,25+3*(k-1)+(1:3)];
    [~,~,MSE,MSE0,Error_store{k},Error0_store{k}]=my_plane_delta(...
        a_d_alpha_theta0,P0(k,:),L,beta0(k,:),planeOffset(k),data{k},z{k},T1{k},PH1,false);
    cable_plane_store(1,k)=sqrt(MSE/N(k));
    plane_store(1,k)=sqrt(MSE0/N(k));
end
MSE_store(1)=sqrt(mean(vertcat(Error_store{:}).^2));
MSE_store0(1)=sqrt(mean(vertcat(Error0_store{:}).^2));
objective_store(1)=(MSE_store(1)^2+planeWeight*MSE_store0(1)^2)/2;
nParameter=25+3*nPlane;% 3个平面时为34维：24个DH、L、3×(法向量2维+偏置1维)
J_prior=diag([KH1*ones(1,24),KH2,zeros(1,3*nPlane)]);
converged=false;

%------------------------------------------
%% 四、联合迭代：同一轮汇总所有平面，更新唯一一组DH参数
% 实际目标F = mean(e^2 + planeWeight*c^2)/2
%             + KH1*norm(DH-DH标称)^2/2 + KH2*(L-L0)^2/2。
% e为拉线残差，c为有符号平面距离；ADMM通过c=z处理带噪声的平面约束。
% 内层固定z、T1修正原变量；外层再用最新残差更新z、T1。
for iteration=1:Iter
    parameters_old=[a_d_alpha_theta0;L;beta0(:);planeOffset];
    for inner=1:8
        delta0=zeros(nParameter,1);
        delta1=zeros(nParameter,nParameter);
        MSE=0;
        MSE0=0;
        for k=1:nPlane
            [delta0_k,delta1_k,MSE_k,MSE0_k]=my_plane_delta(...
                a_d_alpha_theta0,P0(k,:),L,beta0(k,:),planeOffset(k),data{k},z{k},T1{k},PH1,true);
            % 联合训练的关键：共同DH/L的梯度相加，各平面独立参数各归其位。
            % 完整delta1保留DH、L和平面参数之间的交叉项。
            delta0(index{k})=delta0(index{k})+delta0_k;
            delta1(index{k},index{k})=delta1(index{k},index{k})+delta1_k;
            MSE=MSE+MSE_k;
            MSE0=MSE0+MSE0_k;
        end
        delta_prior=[a_d_alpha_theta0-a_d_alpha_theta0_norm0;L-L0;zeros(3*nPlane,1)];
        delta0=delta0/N_total+J_prior*delta_prior;
        % 单平面函数返回求和项；全部汇总后仅除一次总样本数，正则项仅加一次。
        delta1=delta1/N_total+J_prior;
        Cost=(MSE+PH1*MSE0)/(2*N_total)+delta_prior'*J_prior*delta_prior/2;
        accepted=false;
        for trial=1:12
            step=-(delta1+KH5*eye(nParameter))\delta0;
            % Gauss-Newton/LM增量：用阻尼方程求解，避免直接求逆。
            step=step/max(1,max(abs(step))/0.02);
            a_d_alpha_theta0_try=a_d_alpha_theta0+step(1:24);
            L_try=L+step(25);
            beta0_try=beta0;
            planeOffset_try=planeOffset;
            MSE_try=0;
            MSE0_try=0;
            for k=1:nPlane
                B=null(beta0(k,:));
                % 法向量只有2个独立方向：先在切平面修正，再恢复单位长度。
                beta0_try(k,:)=beta0(k,:)+(B*step(index{k}(26:27)))';
                beta0_try(k,:)=beta0_try(k,:)/norm(beta0_try(k,:));
                planeOffset_try(k)=planeOffset(k)+step(index{k}(28));
                [~,~,MSE_k,MSE0_k]=my_plane_delta(...
                    a_d_alpha_theta0_try,P0(k,:),L_try,beta0_try(k,:),planeOffset_try(k),...
                    data{k},z{k},T1{k},PH1,false);
                MSE_try=MSE_try+MSE_k;
                MSE0_try=MSE0_try+MSE0_k;
            end
            delta_prior_try=[a_d_alpha_theta0_try-a_d_alpha_theta0_norm0;L_try-L0;zeros(3*nPlane,1)];
            Cost_try=(MSE_try+PH1*MSE0_try)/(2*N_total)+delta_prior_try'*J_prior*delta_prior_try/2;
            % 接受条件看含正则的增广子问题目标，不是单独的拉线RMSE。
            % 平面数据存在大离群值时，总目标下降仍可能伴随拉线误差上升。
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

    % 【五】用最新参数计算残差，再更新各平面的噪声变量和乘子
    % delta4累加实际目标F的梯度，用于驻点检查，此处不叠加旧的对偶项。
    delta4=zeros(nParameter,1);
    primalSum=0;
    dualSum=0;
    zSum=0;
    T1Sum=0;
    for k=1:nPlane
        zero=zeros(N(k),1);
        [delta4_k,~,~,~,Error_store{k},Error0_store{k}]=my_plane_delta(...
            a_d_alpha_theta0,P0(k,:),L,beta0(k,:),planeOffset(k),data{k},zero,zero,planeWeight,true);
        delta4(index{k})=delta4(index{k})+delta4_k;
        z_old=z{k};
        % z是允许存在的测量噪声残差，下面是平方平面误差对应的近端更新。
        % T1是逐样本对偶变量，采用上升更新；它不与DH参数一起做最小化。
        z{k}=PH1/(PH1+planeWeight)*(Error0_store{k}+T1{k}/PH1);
        delta8=PH1*(Error0_store{k}-z{k});
        T1{k}=T1{k}+delta8;
        primalSum=primalSum+sum((Error0_store{k}-z{k}).^2);
        dualSum=dualSum+PH1^2*sum((z{k}-z_old).^2);
        zSum=zSum+sum(z{k}.^2);
        T1Sum=T1Sum+sum(T1{k}.^2);
        x0(k,:)=planeOffset(k)*beta0(k,:);
        cable_plane_store(iteration+1,k)=sqrt(mean(Error_store{k}.^2));
        plane_store(iteration+1,k)=sqrt(mean(Error0_store{k}.^2));
    end
    delta_prior=[a_d_alpha_theta0-a_d_alpha_theta0_norm0;L-L0;zeros(3*nPlane,1)];
    stationarityNorm=norm(delta4/N_total+J_prior*delta_prior,inf);
    MSE_store(iteration+1)=sqrt(mean(vertcat(Error_store{:}).^2));
    MSE_store0(iteration+1)=sqrt(mean(vertcat(Error0_store{:}).^2));
    objective_store(iteration+1)=(MSE_store(iteration+1)^2+planeWeight*MSE_store0(iteration+1)^2)/2+...
        delta_prior'*J_prior*delta_prior/2;
    primal_store(iteration)=sqrt(primalSum/N_total);
    % 原始残差=c-z；对偶残差=PH1*(z-z_old)，均按全部样本计算RMS。
    dual_store(iteration)=sqrt(dualSum/N_total);
    primalTolerance=1e-8+1e-4*max(MSE_store0(iteration+1),sqrt(zSum/N_total));
    dualTolerance=1e-8+1e-4*sqrt(T1Sum/N_total);
    parameterChange=norm([a_d_alpha_theta0;L;beta0(:);planeOffset]-parameters_old,inf);
    objectiveChange=abs(objective_store(iteration+1)-objective_store(iteration))/...
        max(objective_store(iteration),eps);
    if iteration==1 || mod(iteration,10)==0
        fprintf('Iteration %d: cable RMSE=%.6g m, plane RMSE=%.6g m\n',...
            iteration,MSE_store(iteration+1),MSE_store0(iteration+1));
    end
    % 同时检查约束、目标变化、参数变化及梯度，避免只凭曲线变平就停止。
    % converged表示数值条件满足；标定是否有效仍需看拉线精度和独立测试。
    if iteration>=10 && primal_store(iteration)<=primalTolerance && ...
            dual_store(iteration)<=dualTolerance && objectiveChange<1e-6 && ...
            parameterChange<1e-6 && stationarityNorm<gradientTolerance
        converged=true;
        break
    end
end
MSE_store=MSE_store(1:iteration+1);
MSE_store0=MSE_store0(1:iteration+1);
cable_plane_store=cable_plane_store(1:iteration+1,:);
plane_store=plane_store(1:iteration+1,:);
objective_store=objective_store(1:iteration+1);
primal_store=primal_store(1:iteration);
dual_store=dual_store(1:iteration);

%------------------------------------------
%% 六、评价：分别报告各平面和合并数据的训练/测试误差
% 合并RMSE要先拼接全部残差再计算，不能直接平均各平面的RMSE。
% 测试集仅在训练完成后评价，本段不会反向修改参数。
Error_test=cell(nPlane,1);
training_metrics=zeros(nPlane+1,3);% 三列依次为RMSE、MAX、MEAN，单位m
test_metrics=nan(nPlane+1,3);
for k=1:nPlane
    e=Error_store{k};
    training_metrics(k,:)=[sqrt(mean(e.^2)),max(abs(e)),mean(abs(e))];
    Nt=size(data_test{k},1);
    if Nt>0
        zero=zeros(Nt,1);
        [~,~,~,~,Error_test{k}]=my_plane_delta(a_d_alpha_theta0,P0(k,:),L,beta0(k,:),...
            planeOffset(k),data_test{k},zero,zero,PH1,false);
        e=Error_test{k};
        test_metrics(k,:)=[sqrt(mean(e.^2)),max(abs(e)),mean(abs(e))];
    end
end
e=vertcat(Error_store{:});
training_metrics(end,:)=[sqrt(mean(e.^2)),max(abs(e)),mean(abs(e))];
e_test=vertcat(Error_test{:});
if ~isempty(e_test)
    test_metrics(end,:)=[sqrt(mean(e_test.^2)),max(abs(e_test)),mean(abs(e_test))];
end
format long
disp('Calibrated Parameters:'); disp(a_d_alpha_theta0);
disp('P0: one row per plane'); disp(P0);
disp('L ='); disp(L);
disp('x0: one row per plane'); disp(x0);
disp('beta0: one row per plane'); disp(beta0);
fprintf('Iterations: %d, converged: %d\n',iteration,converged);
fprintf('Cable training RMSE: %.9f -> %.9f m\n',MSE_store(1),MSE_store(end));
fprintf('Plane training RMSE: %.9f -> %.9f m\n',MSE_store0(1),MSE_store0(end));
fprintf('Total regularized objective: %.9g -> %.9g\n',objective_store(1),objective_store(end));
if MSE_store(end)>MSE_store(1)
    warning('main3:CableFitWorse',...
        'Cable training RMSE increased from %.6g to %.6g mm. Inspect data and plane residuals before using these parameters.',...
        1000*MSE_store(1),1000*MSE_store(end));
end
fprintf('\nTraining errors (m):          RMSE              MAX             MEAN\n');
for k=1:nPlane
    fprintf('%-8s         %.9f      %.9f      %.9f\n',sheetList{k},training_metrics(k,:));
end
fprintf('ALL              %.9f      %.9f      %.9f\n',training_metrics(end,:));
if ~isempty(e_test)
    fprintf('\nHeld-out test errors (m):     RMSE              MAX             MEAN\n');
    for k=1:nPlane
        fprintf('%-8s         %.9f      %.9f      %.9f\n',sheetList{k},test_metrics(k,:));
    end
    fprintf('ALL              %.9f      %.9f      %.9f\n',test_metrics(end,:));
    final_metrics=test_metrics(end,:);
else
    final_metrics=training_metrics(end,:);
end
if ~converged
    fprintf('Iteration limit reached; inspect residuals before declaring convergence.\n');
end
toc
%% 七、绘图及最终指标：区分训练曲线、总目标和测试指标
% Figure 1画拉线训练RMSE，Figure 2画各平面训练RMSE，均不是总目标F。
figure(1),clf(1)
semilogy(0:iteration,MSE_store,'rx-');
xlabel('Iteration'); ylabel('Cable training RMSE (m)'); grid on
ylim([0.9*min(MSE_store),1.1*max(MSE_store)]);
figure(2),clf(2)
semilogy(0:iteration,plane_store,'LineWidth',1.2);
xlabel('Iteration'); ylabel('Plane training RMSE (m)'); grid on
legend(sheetList,'Location','best');
ylim([0.8*min(plane_store(:)),1.2*max(plane_store(:))]);
% 最后的RMSE、MAX、MEAN默认对应合并独立测试集；没有测试集时对应训练集。
% RMSE=sqrt(mean(e.^2))；MAX=max(abs(e))；MEAN=mean(abs(e))，输出单位均为m。
RMSE=final_metrics(1);
MAX=final_metrics(2);
MEAN=final_metrics(3);
fprintf('\nRMSE = %.9f m\nMAX  = %.9f m\nMEAN = %.9f m\n',RMSE,MAX,MEAN);

%% Repository output export (metrics remain cable residuals, in metres)
outputDir=fullfile(projectDir,'..','..','outputs');
if ~isfolder(outputDir), mkdir(outputDir); end
metricLabels=[sheetList,{'ALL'}]';
trainingTable=array2table(training_metrics,'VariableNames',{'RMSE_m','MAX_m','MEAN_m'},'RowNames',metricLabels);
testTable=array2table(test_metrics,'VariableNames',{'RMSE_m','MAX_m','MEAN_m'},'RowNames',metricLabels);
writetable(trainingTable,fullfile(outputDir,'training_metrics.csv'),'WriteRowNames',true);
writetable(testTable,fullfile(outputDir,'test_metrics.csv'),'WriteRowNames',true);
save(fullfile(outputDir,'calibration_run.mat'),'a_d_alpha_theta0','P0','L','beta0','planeOffset',...
 'training_metrics','test_metrics','trainRows','testRows','randomSeed','trainRatio','converged',...
 'MSE_store','MSE_store0','objective_store','primal_store','dual_store');
exportgraphics(figure(1),fullfile(outputDir,'cable_training_curve.png'));
exportgraphics(figure(2),fullfile(outputDir,'plane_training_curve.png'));
