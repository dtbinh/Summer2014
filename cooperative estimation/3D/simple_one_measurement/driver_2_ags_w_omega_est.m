%% tries to use the current agent's angular velocity measurement and
% an estimate of the other's angular velocity to propagate
% do not know if it will or can work.

clear variables;
close all;

addpath('../../2D');
addpath('../');

%% generate data

if ~exist('data_3d.mat','file');
    
    % sample time
    Ts = 0.02;
    % sim time
    Tmax = 120;
    
    % allowed position space
    R = 10;
    % target average speed
    Vb = 1;
    % number of agents
    N = 2;
    
    % data storage
    T = 0:Ts:Tmax;
    Yc = cell(N,1);
    
    for II = 1:N
        
        % initialize
        r = rand*2*R-R;
        theta = rand*2*pi - pi;
        phi = (rand-0.5)*pi;
        
        r0 = [r*cos(phi)*cos(theta);
            r*cos(phi)*sin(theta);
            r*sin(phi)];
        v0 = [0;0;0];
        q0 = rand(4,1);q0 = q0./norm(q0);
        garb = attparsilent(q0,[6 4],struct('seq',[1; 2; 1]));
        eul0 = garb(:,1);
        eul0dot = [0;0;0];
        
        tnow = 0;
        
        Y = zeros(length(T),13);% r1 r2 r3 v1 v2 v3 quat omega
        count = 0;
        while(count < length(T))
            
            % pick a point in the space
            r = rand*2*R-R;
            theta = rand*2*pi - pi;
            phi = (rand-0.5)*pi;
            
            rf = [r*cos(phi)*cos(theta);
                r*cos(phi)*sin(theta);
                r*sin(phi)];
            vf = [0;0;0];
            % final time
            Tf = norm(rf-r0)/Vb;
            Tf = round(Tf/Ts)*Ts;% round to nearest sample time for simplicity
            % r0 proscribed
            
            % time vector, relative to last move
            t = 0:Ts:Tf;
            
            % generate coefficients for reference traj
            BC = [1 0 0 0;0 1 0 0;1 Tf Tf^2 Tf^3;0 1 2*Tf 3*Tf^2];
            for i = 1:3
                % coefficients
                vc(:,i) = BC\[r0(i);v0(i);rf(i);vf(i)];
            end
            
            % reference attitude
            vran = rand(3,1);vran = vran./norm(vran);
            ref1 = [0 1 2 3]*vc;ref1 = ref1./norm(ref1);% body 1-axis reference, in inertial frame
            ref2 = cross(ref1,vran);ref2 = ref2./norm(ref2);
            ref3 = cross(ref1,ref2);
            Cbn = [ref1' ref2' ref3']';
            
            % reference quaternion, scalar first
            qref = attparsilent(Cbn,[1 6]);
            garb = attparsilent(Cbn,[1 4],struct('seq',[1 2 1]'));
            eulref = garb(:,1);
            
            A = 2;
            
            eulref = minangle(eulref,eul0);
            
            eq = eul0 - eulref;
            
            lt = (1:length(t));
            if count+length(t) > length(T)
                lt = 1:(length(T)-count);
                t = t(lt);
            end
            
            qu = zeros(length(t),4);
            %eul = zeros(length(t),3);
            %euldot = zeros(length(t),3);
            omega = zeros(length(t),3);
            
            rc = zeros(4,3);
            for i = 1:3
                %just do a polynomial for this also
                rc(:,i) = BC\[eul0(i);eul0dot(i);eulref(i);0];
                
                %eul(:,i) = eq(i)*exp(-A*t) + eulref(i);
                %euldot(:,i) = -A*eq(i)*exp(-A*t);
            end
            eul = [ones(length(t),1) t' t.^2' t.^3']*rc;
            euldot = [zeros(length(t),1) ones(length(t),1) 2*t' 3*t.^2']*rc;
            for i = 1:length(t)
                omega(i,:) = ([euldot(i,3);0;0] + DCMConverter(1,eul(i,3))*[0;euldot(i,2);0] + DCMConverter(1,eul(i,3))*DCMConverter(2,eul(i,2))*[euldot(i,1);0;0])';
                qu(i,:) = attparsilent([eul(i,:)' [1;2;1]],[4 6])';
            end
            
            Y(count+lt,1:3) = [ones(length(t),1) t' t.^2' t.^3']*vc;
            Y(count+lt,4:6) = [zeros(length(t),1) ones(length(t),1) 2*t' 3*t.^2']*vc;
            Y(count+lt,7:10) = qu;
            Y(count+lt,11:13) = omega;
            Y(count+lt,14:16) = eul;            
            
            count = count+length(lt);
            tnow = tnow + t(end);
            
            % reset for next iteration
            r0 = Y(count,1:3)';
            v0 = Y(count,4:6)';
            q0 = Y(count,7:10)';
            eul0 = eul(end,:)';
            eul0dot = euldot(end,:)';
        end
        
        Y(:,7:10) = quatmin(Y(:,7:10));
        
        Yc{II} = Y;
    end
    
    save data_3d.mat;
else
    load data_3d.mat;
end
%% generate measurements for each 
if ~exist('meas','var')
    
    % error stdev
    err_dev = 0.001;%rads
    
    meas = cell(N,1);
    for II = 1:N
        meas{II} = zeros(length(T),(N-1)*3);
        Jcount = 0;
        for JJ = [1:II-1 II+1:N]
            Jcount = Jcount+1;
            % inertial vector from II to JJ
            rdiff = Yc{JJ}(:,1:3) - Yc{II}(:,1:3);
            % convert to body frame
            rsee = zeros(size(rdiff));
            rmeas = zeros(size(rdiff));
            for i = 1:length(T)
                quat = Yc{II}(i,7:10)';
                Cbn = attparsilent(quat,[6 1]);
                rsee(i,:) = rdiff(i,:)*Cbn';
                
                % generate error angle
                delta = randn*err_dev;
                
                % get arbitrary axis of rotation
                vec = rand(3,1);vec = vec./norm(vec);
                
                % get DCM from true to error "frame"
                Crp_r = attparsilent([vec [delta;0;0]],[2 1]);
                
                rmeas(i,:) = rsee(i,:)*Crp_r;
                % use the unit vector as the measurement
                rmeas(i,:) = rmeas(i,:)./norm(rmeas(i,:));
            end
            
            meas{II}(:,(Jcount-1)*3+(1:3)) = rmeas;
        end
    end
    save data_3d.mat;
end
%% process

% compute truth
qji = zeros(length(T),4);
for k = 1:length(T)
    Cin = attparsilent(Yc{1}(k,7:10)',[6 1]);
    Cjn = attparsilent(Yc{2}(k,7:10)',[6 1]);
    Cji = Cjn*Cin';
    qji_tr = attparsilent(Cji,[1 6]);
    qji(k,:) = qji_tr';
end
qji = quatmin(qji);

xh = cell(2,1);
Ph = cell(2,1);

tv = sort([T T T(end)+Ts]);

for i = 1:2
    xh{i} = zeros(length(tv),7);
    Ph{i} = zeros(length(tv),49);
    %xh{i}(1,:) = [1 0 0 0];
    xh{i}(1,1:4) = randn(4,1);xh{i}(1,:) = xh{i}(1,:)./norm(xh{i}(1,:));
    xh{i}(1,5:7) = 0;% initialize ang vel to zero. is estimate of j's ang vel in j's frame
    Ph{i}(1,:) = reshape( eye(7), 49,1)';
end

% use exact initial conditions
xh{1}(1,1:4) = qji(1,:);
xh{1}(1,5:7) = Yc{2}(1,11:13);
xh{2}(1,1:4) = qji(1,:);xh{2}(1,1) = -xh{2}(1,1);
xh{2}(1,5:7) = Yc{1}(1,11:13);

% error covariance associated with my measurement of him, and his
% measurement of me
Rx = zeros(6);
% measurement error
errnom = [0 err_dev err_dev].^2;

% measurement error in other agent's omega
Qk = diag([1e-2*Ts^2*[1 1 1] ...% component for measured ang. vel uncertainty
    (0.22*Ts)^2*[1 1 1]]);% component for estimated ang. vel uncertainty

for j = 1:2
    for k = 1:length(T)
        %% update        
        xhat = xh{j}(2*k-1,:)';
        Pk = reshape(Ph{j}(2*k-1,:)',7,7);
        
        ymeas = zeros(3,1);
        
        % estactualimated i to j frame transform
        Cji = attparsilent(xhat(1:4),[6 1]);
        
        % my meas of him
        rji_i = meas{j}(k,(1:3))';
        if j == 1
            % his meas of me
            rij_j = meas{2}(k,(1:3))';
        else 
            rij_j = meas{1}(k,(1:3))';
        end
        % error
        ydiff = rij_j + Cji*rji_i;
        
        % measurement gradient
        Hk = zeros(3,7);
        Hk(:,1) = -2*squiggle(xhat(2:4))*rji_i;
        Hk(:,2:4) = 2*xhat(1)*squiggle(rji_i) - 2*squiggle(xhat(2:4))*squiggle(rji_i) - 2*squiggle( squiggle(xhat(2:4))*rji_i );
        Hk = -Hk;
        
        Crt_b = zeros(3);
        Crt_b(1,:) = rji_i';
        
        % compute an arbitrary frame transfer from the frame aligned with
        % the measurement vector to the body frame
        % the resulting covariance is independent of the other two axes we
        % choose here
        r2 = cross(rji_i,[1;0;0]);r2 = r2./norm(r2);
        r3 = cross(rji_i,r2);
        Crt_b(2,:) = r2';
        Crt_b(3,:) = r3';
        
        % error covariance associated with rji_i
        Rx(1:3,1:3) = Crt_b'*diag(errnom)*Crt_b;
        
        % repeat for rij_j2
        Crt_b = zeros(3);
        Crt_b(1,:) = rij_j';
        r2 = cross(rij_j,[1;0;0]);r2 = r2./norm(r2);
        r3 = cross(rij_j,r2);
        Crt_b(2,:) = r2';
        Crt_b(3,:) = r3';
        
        % error covariance associated with rij_j, in its frame
        Rx(4:6,4:6) = Crt_b'*diag(errnom)*Crt_b;
        
        % jacobian associated with the measurement
        J = zeros(3,6);
        J(1:3,1:3) = -Cji;
        J(1:3,4:6) = -eye(3);
        
        % actual 'measurement' covariance
        Ry = J*Rx*J';
        
        % Kalman gain
        Kk = Pk*Hk'*((Hk*Pk*Hk'+Ry)\eye(3));
        
        %update
        xhat = xhat + Kk*ydiff;
        Pk = (eye(7) - Kk*Hk)*Pk;
        
        % re-normalize
        xhat(1:4) = xhat(1:4)./norm(xhat(1:4));
        
        % store
        xh{j}(2*k,:) = xhat';
        Ph{j}(2*k,:) = reshape(Pk,49,1)';
        %% propagate
        %play it forward
        %xh{j}(2*k+1,:) = xh{j}(2*k,:);
        %Ph{j}(2*k+1,:) = Ph{j}(2*k,:);
        
        xhat = xh{j}(2*k,:)';
        Pk = reshape(Ph{j}(2*k,:)',7,7);
        
        %w = -Yc{j}(k,11:13)';
        if j == 1
            Cji = attparsilent(xhat(1:4),[6 1]);
            % my angular velocity in my frame
            wi = Yc{1}(k,11:13)' + randn(3,1).*diag(sqrtm(Qk(1:3,1:3))/Ts);
            % relative angular velocity in j frame
            w = xhat(5:7) - Cji*wi;
        else
            Cji = attparsilent(xhat(1:4),[6 1]);
            % my angular velocity, measured in my frame
            wi = Yc{2}(k,11:13)' + randn(3,1).*diag(sqrtm(Qk(1:3,1:3))/Ts);
            % relative angular velocity, in j frame
            w = xhat(5:7) - Cji*wi; % my estimate of his angular velocity is in his reference frame
        end
        
        A = 0.5*[ -xhat(2:4)';xhat(1)*eye(3) + squiggle(xhat(2:4))];
        xdot = [A*w;0;0;0];
        
        % need the gradient F
        Fk = zeros(7,7);
        Fk(2:4,1) = 0.5*eye(3)*w;
        Fk(1:4,2) = 0.5*[-1 0 0;squiggle([1;0;0])]*w;
        Fk(1:4,3) = 0.5*[0 -1 0;squiggle([0;1;0])]*w;
        Fk(1:4,4) = 0.5*[0 0 -1;squiggle([0;0;1])]*w;
        Fk(1:4,5:7) = A;
        % account for discretization
        Fk = eye(7) + Ts*Fk;
        
        % need the G matrix
        Gk = zeros(7,6);
        % component for the measured ang. vel error
        Gk(1:4,1:3) = A*Cji;
        Gk(1:4,4:6) = -A;
        % component for the estimated ang. vel uncertainty
        Gk(5:7,4:6) = -eye(3);
        
        % update
        xhat = xhat + Ts*xdot;
        Pk = Fk*Pk*Fk' + Gk*Qk*Gk';
        
        % re-normalize
        xhat(1:4) = xhat(1:4)./norm(xhat(1:4));
        
        % store
        xh{j}(2*k+1,:) = xhat';
        Ph{j}(2*k+1,:) = reshape(Pk,49,1)';
    end
end

%% evaluate results

close all;
figure;

Pdiag = 1:8:49;

qji_in = interp1(T,qji,tv);

xh{1}(:,1:4) = quatmin(xh{1}(:,1:4),qji_in);
xh{2}(:,1:4) = quatmin(xh{2}(:,1:4),[-qji_in(:,1) qji_in(:,2:4)]);

for k = 1:4
    subplot(2,2,k);
    plot(tv,xh{1}(:,k),'--x');
    hold on;
    plot(tv,xh{1}(:,k) + 2*sqrt(Ph{1}(:,Pdiag(k))),'r--');
    plot(tv,xh{1}(:,k) - 2*sqrt(Ph{1}(:,Pdiag(k))),'r--');
    plot(T,qji(:,k),'k-','linewidth',2);
    set(gca,'ylim',[-1 1]);
end

figure;
for k = 1:4
    subplot(2,2,k);
    plot(tv,xh{2}(:,k),'--x');
    hold on;
    plot(tv,xh{2}(:,k) + 2*sqrt(Ph{2}(:,Pdiag(k))),'r--');
    plot(tv,xh{2}(:,k) - 2*sqrt(Ph{2}(:,Pdiag(k))),'r--');
    if k == 1
        plot(T,-qji(:,k),'k-','linewidth',2);
    else
        plot(T,qji(:,k),'k-','linewidth',2);
    end
    set(gca,'ylim',[-1 1]);
end

% compute error quaternions
q_err1 = zeros(length(tv),1);
q_err2 = zeros(length(tv),1);
for i = 1:length(tv)
    %truth
    Cji = attparsilent(qji_in(i,:)',[6 1]);
    Cji_1 = attparsilent(xh{1}(i,:)',[6 1]);
    Cij_2 = attparsilent(xh{2}(i,:)',[6 1]);
    % error DCMs
    Ct_1 = Cji_1'*Cji;
    Ct_2 = Cij_2'*Cji';
    %error quaternions
    gar1 = attparsilent(Ct_1,[1 2]);
    q_err1(i) = gar1(1,2);
    gar2 = attparsilent(Ct_2,[1 2]);
    q_err2(i) = gar2(1,2);
end
%%
figure;

subplot(211);
plot(tv, q_err1);
ylabel('agent 1 pointing error (rad)');

subplot(212);
plot(tv, q_err2);
ylabel('agent 2 pointing error (rad)');

% angular velocity
w1_interp = interp1(T,Yc{1}(:,11:13),tv);
w2_interp = interp1(T,Yc{2}(:,11:13),tv);
figure;
subplot(211);
plot(tv,w2_interp - xh{1}(:,5:7));
hold on;
%plot(tv,sqrt(Ph{1}(:,Pdiag(5:7)))*3,'r--');
%plot(tv,-sqrt(Ph{1}(:,Pdiag(5:7)))*3,'r--');
ylabel('agent 1 angular velocity estimate error');

subplot(212);
plot(tv,w1_interp - xh{2}(:,5:7));
hold on;
%plot(tv,sqrt(Ph{2}(:,Pdiag(5:7)))*3,'r--');
%plot(tv,-sqrt(Ph{2}(:,Pdiag(5:7)))*3,'r--');
ylabel('agent 2 angular velocity estimate error');