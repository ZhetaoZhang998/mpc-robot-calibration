function [delta0,delta1,MSE,MSE0,Error_store,Error0_store]=my_plane_delta(...
    a_d_alpha_theta0,P0,L,beta0,planeOffset,data,z,T1,PH1,needJ)
% 单个平面的计算：逐点计算误差，并累加delta。
% data为该平面的8列原始数据；needJ=false时只计算误差，用于步长检查。
% 返回的是求和结果，主程序汇总所有平面后统一除以总样本数。
% 局部修正量顺序：24个DH参数、L、法向量的2个方向、平面偏置。
% P0是当前平面的固定点（一行3列）；DH和L由主程序在所有平面间共享。
% 输出MSE=sum(Error.^2)，MSE0=sum(Error1.^2)，它们是平方和而不是RMSE。

N=size(data,1);
delta0=zeros(28,1);
delta1=zeros(28,28);
MSE=0;
MSE0=0;
Error_store=zeros(N,1);
Error0_store=zeros(N,1);
B=null(beta0);
% B为3×2矩阵，两列均与法向量垂直，对应法向量的两个独立修正方向。
for i=1:N
    q=pi/180*data(i,1:6)';
    % 【1】统一单位：关节角转rad，实测拉线长度和百分表读数转m。
    L_ex1=data(i,7)/1000;
    K=data(i,8)/1000;
    if needJ
        [Pos_norm1,J_norm4]=my_forward_main2(a_d_alpha_theta0,q);
    else
        Pos_norm1=my_forward_main2(a_d_alpha_theta0,q);
    end
    L_norm1=norm(Pos_norm1-P0');
    % 【2】拉线残差：预测距离减去实测距离。
    Error=L_norm1-L_ex1;
    if needJ
        J_norm1=[(Pos_norm1'-P0)/max(L_norm1,eps)*J_norm4,zeros(1,4)];
        % 距离对位置的导数乘位置雅可比；末尾4个零表示不依赖L和平面参数。
    end

    % 【3】接触点模型中给d6增加L-K；拉线距离仍用原DH参数计算。
    MM=zeros(24,1);
    MM(12)=L-K;% 按实际装配方向，百分表补偿加到d6
    X=a_d_alpha_theta0+MM;
    if needJ
        [Pos_norm0,J_norm4]=my_forward_main2(X,q);
        J_norm0=[beta0*J_norm4,beta0*J_norm4(:,12),Pos_norm0'*B,-1];
        % 分块对应DH、L、法向量切向2维、偏置；对L求导使用d6列J_norm4(:,12)。
    else
        Pos_norm0=my_forward_main2(X,q);
    end
    % 【4】Error0是真实平面距离c；Error1是ADMM子问题中的偏移残差。
    % beta0必须为单位向量，Error0才可直接解释为有符号距离。
    Error0=Pos_norm0'*beta0'-planeOffset;
    Error1=Error0-z(i)+T1(i)/PH1;
    if needJ
        delta0=delta0+J_norm1'*Error+PH1*J_norm0'*Error1;
        % 【5】delta0为梯度，delta1为正半定的Gauss-Newton近似Hessian，均逐点累加。
        % 两项均以正号累加；各参数导数应有的负号已包含在雅可比中。
        delta1=delta1+J_norm1'*J_norm1+PH1*(J_norm0'*J_norm0);
    end
    MSE=MSE+Error^2;
    MSE0=MSE0+Error1^2;
    % 原始残差单独保存，用于评价、异常点定位及z/T1更新。
    Error_store(i)=Error;
    Error0_store(i)=Error0;
end
end
