clear all
close all  
%使用符号函数建立实际模型，方便求导
syms d1 d2 d3 d4 d5 d6;   %机械臂连杆偏移d
syms a1 a2 a3 a4 a5 a6;     %机械臂连杆长度a
syms theta0_1 theta0_2 theta0_3 theta0_4 theta0_5 theta0_6; %关节角零位
syms alpha1 alpha2 alpha3 alpha4 alpha5 alpha6; %alpha
syms q1 q2 q3 q4 q5 q6;    %转动角度
syms x1 y1 z1;
syms x2 y2 z2;
syms x3 y3 z3;
%------------------------------------------
%create robot model机器人通用模型的建立（用符号化参数）
my_link(1) = Link([0, d1, a1, alpha1, 0], 'standard');%the last entry 0 means the joint is revolute,1 means primatic
my_link(2) = Link([0, d2, a2, alpha2, 0], 'standard');
my_link(3) = Link([0, d3, a3, alpha3, 0], 'standard');
my_link(4) = Link([0, d4, a4, alpha4, 0], 'standard');
my_link(5) = Link([0, d5, a5, alpha5, 0], 'standard');
my_link(6) = Link([0, d6, a6, alpha6, 0], 'standard');
Robot_model= SerialLink(my_link, 'name', 'robot_ex');   

%------------------------------------------
%符号运算
Pos = Robot_model.fkine([q1+theta0_1, q2+theta0_2, q3+theta0_3, q4+theta0_4, q5+theta0_5, q6+theta0_6]).t;   %实验的机械臂位置
P0=[x1; y1; z1];%标定点
x0=[x2; y2; z2];%平面上的点
beta0=[x3; y3; z3];%平面法向量
%beta0=beta0/norm(beta0);
L=norm(Pos-P0);
fid = fopen('D:\ceshi.txt', 'wt');
fprintf(fid, 'L=%s;',char(L));
fid = fclose(fid);

J = [...%Jacobian of Pos_norm relative to a,d,alpha,theta0
diff(L, a1), diff(L, a2),diff(L, a3), diff(L, a4),diff(L, a5), diff(L, a6),...
diff(L, d1), diff(L, d2),diff(L, d3), diff(L, d4), diff(L,d5), diff(L, d6),...
diff(L,alpha1), diff(L,alpha2),diff(L,alpha3), diff(L,alpha4), diff(L,alpha5), diff(L, alpha6),...
diff(L,theta0_1), diff(L,theta0_2),diff(L,theta0_3), diff(L,theta0_4), diff(L,theta0_5), diff(L, theta0_6)];
J1=[diff(L,x1), diff(L,y1),diff(L,z1)];
fid = fopen('D:\csd.txt', 'wt');
fprintf(fid, 'J(1,1)=%s;\n J(1,2)=%s;\n J(1,3)=%s;\n J(1,4)=%s;\n J(1,5)=%s;\n J(1,6)=%s;\n J(1,7)=%s;\n J(1,8)=%s;\n J(1,9)=%s;\n J(1,10)=%s;\n J(1,11)=%s;\n J(1,12)=%s;\n J(1,13)=%s;\n J(1,14)=%s;\n J(1,15)=%s;\n J(1,16)=%s;\n J(1,17)=%s;\n J(1,18)=%s;\n J(1,19)=%s;\n J(1,20)=%s;\n J(1,21)=%s;\n J(1,22)=%s;\n J(1,23)=%s;\n J(1,24)=%s;',char(J(1,1)),char(J(1,2)),char(J(1,3)),char(J(1,4)),char(J(1,5)),char(J(1,6)),char(J(1,7)),char(J(1,8)),char(J(1,9)),char(J(1,10)),char(J(1,11)),char(J(1,12)),char(J(1,13)),char(J(1,14)),char(J(1,15)),char(J(1,16)),char(J(1,17)),char(J(1,18)),char(J(1,19)),char(J(1,20)),char(J(1,21)),char(J(1,22)),char(J(1,23)),char(J(1,24)));
fid = fclose(fid);
fid = fopen('D:\csaa.txt', 'wt');
fprintf(fid, 'J1(1,1)=%s;\n J1(1,2)=%s;\n J1(1,3)=%s;',char(J1(1,1)),char(J1(1,2)),char(J1(1,3)));
fid = fclose(fid);
% J2=((Pos-x0)'*beta0*(Pos-x0)');
% fid = fopen('D:\csaa2.txt', 'wt');
% fprintf(fid, 'J2(1,1)=%s;\n J2(1,2)=%s;\n J2(1,3)=%s;',char(J2(1,1)),char(J2(1,2)),char(J2(1,3)));
% fid = fclose(fid);

