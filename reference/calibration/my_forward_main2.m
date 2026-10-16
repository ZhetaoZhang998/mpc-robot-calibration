function [Pos,J]=my_forward_main2(a_d_alpha_theta0,q)
% 标准DH正运动学；J为末端位置对24个DH参数的雅可比。
% 参数顺序：[a1~a6, d1~d6, alpha1~alpha6, theta0_1~theta0_6]。
% 单独使用这个函数，保证main2中的位置和雅可比来自同一个模型。
% Pos为基坐标系下3×1末端位置；J为3×24位置雅可比，不是6维位姿雅可比。

T=eye(4);
P=zeros(3,7);% 各关节原点，第一列为基坐标系原点
x=zeros(3,6);% 各连杆的x轴
z=zeros(3,6);% 各关节转动轴，也是对应d参数的方向
for j=1:6
    a=a_d_alpha_theta0(j);
    d=a_d_alpha_theta0(6+j);
    alpha=a_d_alpha_theta0(12+j);
    theta=q(j)+a_d_alpha_theta0(18+j);
    z(:,j)=T(1:3,3);

    % 标准DH顺序：绕z转theta、沿z移d、沿x移a、绕x转alpha。
    A=[cos(theta),-sin(theta)*cos(alpha), sin(theta)*sin(alpha),a*cos(theta);...
       sin(theta), cos(theta)*cos(alpha),-cos(theta)*sin(alpha),a*sin(theta);...
       0,          sin(alpha),            cos(alpha),           d;...
       0,          0,                     0,                    1];
    T=T*A;
    P(:,j+1)=T(1:3,4);
    x(:,j)=T(1:3,1);
end
Pos=P(:,7);

if nargout>1
    % 长度参数沿对应轴求导，角度参数用轴与末端位移的叉积。
    % J(:,12)对应d6，方向为第6个关节之前的z5轴。
    J=zeros(3,24);
    for j=1:6
        J(:,j)=x(:,j);% 对a_j求导
        J(:,6+j)=z(:,j);% 对d_j求导
        J(:,12+j)=cross(x(:,j),Pos-P(:,j+1));% 对alpha_j求导
        J(:,18+j)=cross(z(:,j),Pos-P(:,j));% 对theta0_j求导
    end
end
end
