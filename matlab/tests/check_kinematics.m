% Actual MATLAB helper verification. Not executed during package preparation.
testDir=fileparts(mfilename('fullpath'));
previousPath=path; cleanup=onCleanup(@()path(previousPath));
addpath(fullfile(testDir,'..','calibration'),'-begin');
rng(17);
p=[.24985003 .90032123 -.20614449 0 0 0 .6535 0 0 1.03037534 0 .2006 -1.571 0 1.571 -1.571 1.571 0 0 0 0 0 0 0]';
h=1e-6;
for k=1:8
 q=2*pi*(rand(6,1)-.5);
 [pos,J]=my_forward_main2(p,q);
 Jfd=zeros(3,24);
 for j=1:24
  pp=p; pm=p; pp(j)=pp(j)+h; pm(j)=pm(j)-h;
  Jfd(:,j)=(my_forward_main2(pp,q)-my_forward_main2(pm,q))/(2*h);
 end
 assert(all(isfinite(J(:))) && all(isfinite(pos)));
 assert(max(abs(J(:)-Jfd(:)))<1e-6,'Position Jacobian finite-difference mismatch.');
 assert(abs(norm(J(:,12))-1)<1e-10,'d6 direction must have unit norm.');
 pp=p;pp(12)=pp(12)+.02;
 assert(norm(my_forward_main2(pp,q)-(pos+.02*J(:,12)))<1e-10,'Probe compensation mismatch.');
end
fprintf('Kinematics finite-difference and d6 compensation checks passed.\n');
