function [P0,MSE_store1]=my_fit_anchor(a_d_alpha_theta0,data)
% 用传入的训练数据拟合一个拉线固定点P0。
% 不同平面采集时移动过固定点，主程序应分别调用本函数。
% 本函数只估计P0，保持传入的DH参数不变，也不读取测试集。
% 目标：min_P0 mean((norm(Pos_i-P0)-L_ex_i)^2)/2。
N=size(data,1);
Pos_batch=zeros(N,3);
% 当前机器人模型的末端位置只计算一次，后续循环仅调整固定点xyz。
for i=1:N
    q=pi/180*data(i,1:6)';
    Pos_batch(i,:)=my_forward_main2(a_d_alpha_theta0,q)';
end
L_ex11=data(:,7)/1000;
xyz=[2 1.5 0.05];
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
        delta3=delta3+J_norm0'*J_norm0;
        MSE1=MSE1+Error^2;
    end
    delta2=delta2/N;
    delta3=delta3/N;
    MSE1=MSE1/N;
    MSE_store1(iteration)=MSE1;
    accepted=false;
    for trial=1:12
        % 实际平方误差下降才接受；否则增大阻尼，缩短下一次尝试的步长。
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
P0=xyz;
MSE_store1=MSE_store1(1:iteration);
% MSE_store1保存均方误差，单位m^2；与主程序保存的RMSE历史区分。
end
